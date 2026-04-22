#pragma once

#include <oboe/Oboe.h>

#include <array>
#include <atomic>
#include <memory>
#include <mutex>
#include <vector>

namespace stack_looper {

// Maximum number of simultaneously-loaded tracks. Bumping this is cheap but
// each track pre-allocates kMaxTrackSeconds * sample_rate floats so pick a
// sensible value.
constexpr int kMaxTracks = 4;
constexpr int kMaxTrackSeconds = 30;

// Lock-free SPSC (single-producer/single-consumer) ring buffer of floats.
// The INPUT callback is the only writer; the OUTPUT callback is the only
// reader. Capacity is rounded up to the next power of two so we can mask
// instead of mod.
class MicRing {
 public:
  explicit MicRing(size_t min_capacity);

  // Input-callback side. Drops oldest samples if full (ring overflows only
  // under extreme underruns, in which case those samples are already useless).
  void Write(const float* src, int32_t n);

  // Output-callback side. Returns the number of samples actually read.
  int32_t Read(float* dst, int32_t n);

  // Output-callback side. Discards up to [n] samples (or all if n<0), the
  // same as Read but without copying. Used when we want to align recording
  // with "right now" — any samples already sitting in the ring are stale.
  void DiscardAll();

  // Number of samples currently readable. Atomic-safe snapshot.
  int32_t Available() const;

 private:
  std::vector<float> data_;
  size_t mask_;
  std::atomic<uint64_t> write_pos_{0};
  std::atomic<uint64_t> read_pos_{0};
};

// Per-track state. The audio thread reads/writes buffer and write_pos; the
// control thread arms / queries. state_ is the synchronization primitive —
// see the state transitions in engine.cpp.
enum class TrackState : int {
  kEmpty = 0,
  kArmed = 1,      // start_frame scheduled, waiting for transport to reach it
  kRecording = 2,  // actively writing mic samples into buffer
  kRecorded = 3,   // done, buffer holds `length_samples` valid samples
};

struct Track {
  std::vector<float> buffer;          // capacity = kMaxTrackSeconds * sr
  std::atomic<int> state{static_cast<int>(TrackState::kEmpty)};
  int64_t start_frame = 0;            // audio-thread-only once armed
  int32_t length_samples = 0;         // target length; set on arm, const after
  int32_t write_pos = 0;              // audio-thread-only (recording)

  // Playback. playing_ is the synchronization flag: control threads toggle
  // it, the audio thread reads it every callback.
  std::atomic<bool> playing{false};
  int32_t play_pos = 0;               // audio-thread-only
};

// The engine owns one duplex audio pipeline:
//   - an output stream (speaker) that asks us for samples via onAudioReady
//   - an input stream  (mic)     that hands us samples via onAudioReady
//
// Both streams are FLOAT / MONO / 48kHz. They share no state other than the
// master sample clock advanced by the output callback. All real audio work
// (click scheduling, recording, mixing) will be added in later chunks.
//
// Threading model:
//   - Oboe callbacks run on a dedicated real-time audio thread. Code in those
//     callbacks must not lock, allocate, or block.
//   - Control methods (start/stop) are called from the JNI thread. They lock
//     a short mutex for stream lifecycle.
class Engine : public oboe::AudioStreamDataCallback,
               public oboe::AudioStreamErrorCallback {
 public:
  Engine();
  ~Engine() override;

  // Opens (if needed) and starts both streams. Idempotent.
  // Returns oboe::Result::OK on success.
  oboe::Result Start();

  // Stops and closes both streams. Idempotent.
  void Stop();

  bool IsRunning() const { return running_.load(std::memory_order_relaxed); }
  int32_t SampleRate() const { return sample_rate_; }

  // Metronome control. All of these are lock-free and safe to call from the
  // JNI thread while the audio callback is running.
  //
  // SetTempoBpm: update samples-per-beat. Takes effect on the next scheduled
  //              click; clicks already scheduled keep their frame.
  // StartMetronome: begin emitting clicks. The first click fires ~20 ms after
  //                 the next callback boundary so the audio thread can pick it
  //                 up cleanly.
  // StopMetronome:  stop emitting. Any currently-playing click voice finishes
  //                 its tail so we never get a hard cutoff pop.
  void SetTempoBpm(double bpm);
  void StartMetronome();
  void StopMetronome();
  void SetMetronomeAudible(bool audible);

  // Transport position (master sample clock). Useful for Dart to schedule
  // recording "N beats from now" without guessing.
  int64_t CurrentFrame() const {
    return sample_counter_.load(std::memory_order_relaxed);
  }
  int32_t SamplesPerBeat() const {
    return samples_per_beat_.load(std::memory_order_relaxed);
  }

  // Monotonic beat counter. Incremented by the audio thread each time a
  // click fires (regardless of whether metronome_running_ is true — we count
  // from the engine's start). A poll thread in Kotlin reads this via
  // CurrentBeat() to emit EventChannel beat events to Dart.
  int64_t CurrentBeat() const {
    return beat_count_.load(std::memory_order_relaxed);
  }

  // Sample index of the NEXT click the metronome will fire. Snapshots an
  // atomic mirror of the audio thread's internal next_click_frame_. Used
  // by Dart to schedule recording precisely on an upcoming beat without
  // losing sample accuracy to poll/JNI latency.
  int64_t NextClickFrame() const {
    return next_click_frame_atomic_.load(std::memory_order_acquire);
  }

  // Arm a track to record mic samples into its buffer. If [start_frame] has
  // already passed or is in the current buffer, recording begins immediately;
  // otherwise it begins at that exact sample. Overrides any prior arming on
  // the same track. length_frames is clamped to the track's capacity.
  // Returns false on invalid track id.
  bool ArmRecording(int32_t track_id,
                    int64_t start_frame,
                    int32_t length_frames);

  // State queries (lock-free snapshots). Safe from any thread.
  // GetTrackState returns the integer value of a TrackState enum, or -1 for
  // an invalid track id.
  int32_t GetTrackState(int32_t track_id) const;
  int32_t TrackRecordedSamples(int32_t track_id) const;
  std::vector<float> TrackWaveformPeaks(int32_t track_id,
                                        int32_t bucket_count) const;

  // Playback control. Starts or stops looping a recorded track. Calling
  // StartTrackPlayback on a non-recorded track is a no-op. Playback always
  // begins from sample 0 and loops the buffer seamlessly.
  void StartTrackPlayback(int32_t track_id);
  void StopTrackPlayback(int32_t track_id);
  bool IsTrackPlaying(int32_t track_id) const;

  // Clears a track's recording and stops playback. Leaves the pre-allocated
  // buffer alone; only the bookkeeping and state flag are reset.
  void ClearTrack(int32_t track_id);

  // oboe::AudioStreamDataCallback
  oboe::DataCallbackResult onAudioReady(oboe::AudioStream* stream,
                                        void* audio_data,
                                        int32_t num_frames) override;

  // oboe::AudioStreamErrorCallback — log-only for now. A later chunk will
  // auto-recover if the audio device is disconnected (e.g. headphones pulled).
  void onErrorAfterClose(oboe::AudioStream* stream, oboe::Result error) override;

 private:
  oboe::Result OpenOutputStream();
  oboe::Result OpenInputStream();
  void CloseStreams();

  std::mutex lifecycle_mutex_;
  std::shared_ptr<oboe::AudioStream> output_stream_;
  std::shared_ptr<oboe::AudioStream> input_stream_;

  int32_t sample_rate_ = 48000;
  std::atomic<bool> running_{false};

  // Master sample clock, advanced by the OUTPUT callback (one reliable source
  // of truth). Later chunks will use this to schedule beats and loop points
  // with sample accuracy.
  std::atomic<int64_t> sample_counter_{0};

  // Monotonic count of clicks scheduled since engine start. The audio thread
  // bumps this in lockstep with next_click_frame_ advances; the JNI poll
  // thread snapshots it to emit beat events to Dart.
  std::atomic<int64_t> beat_count_{0};

  // ---- Metronome state -----------------------------------------------------
  // Written from control threads, read from audio thread.
  std::atomic<int32_t> samples_per_beat_{24000};  // 120 bpm @ 48 kHz
  std::atomic<bool> metronome_running_{false};
  std::atomic<bool> metronome_audible_{true};
  // Rising-edge flag: when set, audio thread resets next_click_frame_ and
  // clears it. Lets Dart "start" the metronome without racing the callback.
  std::atomic<bool> metronome_start_request_{false};

  // Audio-thread-only state (do NOT touch from other threads):
  int64_t next_click_frame_ = 0;
  // Atomic mirror of next_click_frame_, updated by the audio thread every
  // time the scheduled click frame advances. Read by control threads (via
  // NextClickFrame()) for sample-accurate recording alignment.
  std::atomic<int64_t> next_click_frame_atomic_{0};
  // A click "voice": short sine burst (see kClickLenSamples). The audio
  // thread renders it by stepping click_voice_pos_ from a (possibly negative)
  // start offset through click_len. Any value >= click_len means "inactive".
  // We only need one voice at a time because clicks don't overlap at musical
  // tempi, but the render loop is written so extending to N voices is trivial.
  int32_t click_voice_pos_ = 1 << 30;  // inactive sentinel

  // ---- Recording / mic routing --------------------------------------------
  // Pre-allocated tracks. Buffers are sized on first Start() when we know the
  // real sample rate. Atomic state lets the control thread observe progress
  // without locking.
  std::array<Track, kMaxTracks> tracks_{};

  // Mic ring buffer (SPSC: written by input CB, read by output CB). Allocated
  // on Start(); nullptr when engine is stopped.
  std::unique_ptr<MicRing> mic_ring_;

  // Scratch buffer the output callback uses to drain the mic ring each pass.
  // Pre-allocated to a comfortable burst size so we never touch the heap on
  // the audio thread.
  std::vector<float> mic_scratch_;
};

// Process-wide singleton. Created on first access.
Engine& GetGlobalEngine();

}  // namespace stack_looper
