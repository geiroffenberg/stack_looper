#include "engine.h"

#include <android/log.h>

#include <algorithm>
#include <cstdlib>
#include <cmath>
#include <cstring>

#define LOG_TAG "StackLooperEngine"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace stack_looper {

// Click voice parameters. The click is a short 1 kHz sine burst with a linear
// attack/decay envelope — about 8 ms long. Computed on the fly so we don't
// need a lookup table. Peak amplitude is conservative to leave headroom for
// track playback mixed in later.
namespace {
constexpr float kClickFreqHz = 1000.0f;
constexpr float kClickDurationSec = 0.008f;  // 8 ms
constexpr float kClickPeakAmp = 0.6f;
constexpr float kTwoPi = 6.2831853071795864769f;

// Returns sample index length of a click at the given sample rate.
inline int32_t ClickLenSamples(int32_t sample_rate) {
  return static_cast<int32_t>(kClickDurationSec * sample_rate);
}

// Generates one sample of the click envelope-shaped sine for position [0,len).
inline float RenderClickSample(int32_t pos, int32_t len, int32_t sample_rate) {
  if (pos < 0 || pos >= len) return 0.0f;
  const float t = static_cast<float>(pos) / static_cast<float>(sample_rate);
  const float s = std::sin(kTwoPi * kClickFreqHz * t);
  // Triangular envelope: rises to 1.0 at the midpoint, falls back to 0.
  const float half = 0.5f * len;
  const float env =
      pos < half ? (pos / half) : ((len - 1 - pos) / half);
  return kClickPeakAmp * env * s;
}

// Round up to next power of two (>= 2).
inline size_t NextPow2(size_t x) {
  size_t p = 2;
  while (p < x) p <<= 1;
  return p;
}
}  // namespace

// ---- MicRing ---------------------------------------------------------------

MicRing::MicRing(size_t min_capacity)
    : data_(NextPow2(min_capacity), 0.0f),
      mask_(data_.size() - 1) {}

void MicRing::Write(const float* src, int32_t n) {
  if (n <= 0) return;
  uint64_t w = write_pos_.load(std::memory_order_relaxed);
  const uint64_t r = read_pos_.load(std::memory_order_acquire);
  const size_t cap = data_.size();
  const size_t free_space = cap - static_cast<size_t>(w - r);

  // If the producer would overwrite unread data, bump the read pointer
  // forward. This loses the oldest samples, which is the right behavior:
  // under an output-side stall, ancient mic audio is already useless.
  if (static_cast<size_t>(n) > free_space) {
    const uint64_t drop = static_cast<uint64_t>(n) - free_space;
    read_pos_.store(r + drop, std::memory_order_release);
  }

  for (int32_t i = 0; i < n; ++i) {
    data_[(w + i) & mask_] = src[i];
  }
  write_pos_.store(w + n, std::memory_order_release);
}

int32_t MicRing::Read(float* dst, int32_t n) {
  if (n <= 0) return 0;
  const uint64_t w = write_pos_.load(std::memory_order_acquire);
  uint64_t r = read_pos_.load(std::memory_order_relaxed);
  const int32_t available = static_cast<int32_t>(w - r);
  const int32_t to_read = available < n ? available : n;
  for (int32_t i = 0; i < to_read; ++i) {
    dst[i] = data_[(r + i) & mask_];
  }
  read_pos_.store(r + to_read, std::memory_order_release);
  return to_read;
}

void MicRing::DiscardAll() {
  // Jump the read cursor to the producer's current position. The input
  // callback is allowed to run concurrently; anything written after this
  // load is what the next reader will see, which is exactly what we want.
  const uint64_t w = write_pos_.load(std::memory_order_acquire);
  read_pos_.store(w, std::memory_order_release);
}

int32_t MicRing::Available() const {
  const uint64_t w = write_pos_.load(std::memory_order_acquire);
  const uint64_t r = read_pos_.load(std::memory_order_acquire);
  return static_cast<int32_t>(w - r);
}

// ---- Engine ----------------------------------------------------------------

Engine::Engine() = default;
Engine::~Engine() { Stop(); }

oboe::Result Engine::OpenOutputStream() {
  oboe::AudioStreamBuilder builder;
  builder.setDirection(oboe::Direction::Output)
      ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
      ->setSharingMode(oboe::SharingMode::Exclusive)
      ->setFormat(oboe::AudioFormat::Float)
      ->setChannelCount(oboe::ChannelCount::Mono)
      ->setSampleRate(sample_rate_)
      ->setSampleRateConversionQuality(
          oboe::SampleRateConversionQuality::Medium)
      ->setDataCallback(this)
      ->setErrorCallback(this);

  oboe::Result result = builder.openStream(output_stream_);
  if (result != oboe::Result::OK) {
    LOGE("Failed to open output stream: %s", oboe::convertToText(result));
    return result;
  }

  // Oboe may have negotiated a different sample rate; sync our copy so the
  // input stream (opened next) matches and beat math uses the real rate.
  sample_rate_ = output_stream_->getSampleRate();
  LOGI("Output stream opened: %d Hz, %d ch, frames/burst=%d",
       sample_rate_,
       output_stream_->getChannelCount(),
       output_stream_->getFramesPerBurst());
  return oboe::Result::OK;
}

oboe::Result Engine::OpenInputStream() {
  oboe::AudioStreamBuilder builder;
  builder.setDirection(oboe::Direction::Input)
      ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
      ->setSharingMode(oboe::SharingMode::Exclusive)
      ->setFormat(oboe::AudioFormat::Float)
      ->setChannelCount(oboe::ChannelCount::Mono)
      ->setSampleRate(sample_rate_)
      ->setInputPreset(oboe::InputPreset::Unprocessed)
      ->setDataCallback(this)
      ->setErrorCallback(this);

  oboe::Result result = builder.openStream(input_stream_);
  if (result != oboe::Result::OK) {
    LOGE("Failed to open input stream: %s", oboe::convertToText(result));
    return result;
  }
  LOGI("Input stream opened: %d Hz, %d ch",
       input_stream_->getSampleRate(),
       input_stream_->getChannelCount());
  return oboe::Result::OK;
}

oboe::Result Engine::Start() {
  std::lock_guard<std::mutex> lock(lifecycle_mutex_);
  if (running_.load()) return oboe::Result::OK;

  auto res = OpenOutputStream();
  if (res != oboe::Result::OK) {
    CloseStreams();
    return res;
  }
  res = OpenInputStream();
  if (res != oboe::Result::OK) {
    CloseStreams();
    return res;
  }

  // Now that sample_rate_ is locked in, allocate everything sized to it.
  // Done BEFORE requestStart so the callbacks never see half-initialized state.
  const size_t track_cap =
      static_cast<size_t>(kMaxTrackSeconds) * sample_rate_;
  for (auto& t : tracks_) {
    t.buffer.assign(track_cap, 0.0f);
    t.state.store(static_cast<int>(TrackState::kEmpty),
                  std::memory_order_release);
    t.start_frame = 0;
    t.length_samples = 0;
    t.write_pos = 0;
    t.playing.store(false, std::memory_order_release);
    t.play_pos = 0;
  }
  // 1 second of mic ring is plenty — the output callback drains it every
  // few ms, and overflow just drops stale samples.
  mic_ring_.reset(new MicRing(static_cast<size_t>(sample_rate_)));
  // Scratch sized to one reasonable burst. 4096 handles any real Android
  // device, including phones that pick large burst sizes for HDMI/USB out.
  mic_scratch_.assign(4096, 0.0f);

  // Start INPUT first so mic data is already flowing by the time the output
  // callback begins asking us for samples.
  res = input_stream_->requestStart();
  if (res != oboe::Result::OK) {
    LOGE("input start failed: %s", oboe::convertToText(res));
    CloseStreams();
    return res;
  }
  res = output_stream_->requestStart();
  if (res != oboe::Result::OK) {
    LOGE("output start failed: %s", oboe::convertToText(res));
    CloseStreams();
    return res;
  }

  sample_counter_.store(0, std::memory_order_relaxed);
  beat_count_.store(0, std::memory_order_relaxed);
  running_.store(true, std::memory_order_release);
  LOGI("Engine running");
  return oboe::Result::OK;
}

void Engine::Stop() {
  std::lock_guard<std::mutex> lock(lifecycle_mutex_);
  if (!running_.load()) {
    CloseStreams();
    return;
  }
  running_.store(false, std::memory_order_release);
  CloseStreams();
  LOGI("Engine stopped");
}

void Engine::CloseStreams() {
  if (output_stream_) {
    output_stream_->stop();
    output_stream_->close();
    output_stream_.reset();
  }
  if (input_stream_) {
    input_stream_->stop();
    input_stream_->close();
    input_stream_.reset();
  }
}

oboe::DataCallbackResult Engine::onAudioReady(oboe::AudioStream* stream,
                                              void* audio_data,
                                              int32_t num_frames) {
  if (stream->getDirection() == oboe::Direction::Output) {
    float* out = static_cast<float*>(audio_data);
    std::memset(out, 0, sizeof(float) * num_frames);

    // Snapshot of transport position at the START of this buffer.
    const int64_t buf_start = sample_counter_.load(std::memory_order_relaxed);
    const int64_t buf_end = buf_start + num_frames;

    // Handle a metronome start request: schedule the first click ~20 ms
    // ahead of the current buffer so the callback never misses it.
    if (metronome_start_request_.exchange(false,
                                          std::memory_order_acq_rel)) {
      const int32_t lead = sample_rate_ / 50;  // 20 ms
      next_click_frame_ = buf_start + lead;
      next_click_frame_atomic_.store(next_click_frame_,
                                     std::memory_order_release);
      // Force the click voice to inactive. The schedule loop below will set
      // a proper negative offset when it fires the first click. Using -1
      // here would render an immediate click at this buffer (BUG: caused a
      // double-click at count-in start).
      click_voice_pos_ = 1 << 30;
      metronome_running_.store(true, std::memory_order_release);
    }

    const int32_t click_len = ClickLenSamples(sample_rate_);
    const int32_t spb =
        samples_per_beat_.load(std::memory_order_relaxed);
    const bool metronome_on =
        metronome_running_.load(std::memory_order_acquire);
    const bool metronome_audible =
      metronome_audible_.load(std::memory_order_acquire);

    // 1) Fire off any new click voices whose start frame falls in this buffer.
    //    A while-loop handles pathological cases where spb < num_frames.
    //    beat_count_ is bumped for each click scheduled so a poll thread can
    //    emit beat events to Dart without touching the audio callback path.
    if (metronome_on && spb > 0) {
      while (next_click_frame_ < buf_end) {
        if (next_click_frame_ >= buf_start) {
          // Start a new voice at offset (next_click_frame_ - buf_start).
          // Encoding: negative voice_pos_ means "starts in |pos| samples";
          // we just increment by 1 per frame and begin rendering once >= 0.
          // If the previous voice hasn't finished, overwrite — musically
          // impossible at any reasonable tempo since spb >> click_len.
          if (metronome_audible) {
            click_voice_pos_ =
                -static_cast<int32_t>(next_click_frame_ - buf_start);
          }
          beat_count_.fetch_add(1, std::memory_order_release);
        }
        next_click_frame_ += spb;
      }
      // Publish the updated schedule for control-thread readers.
      next_click_frame_atomic_.store(next_click_frame_,
                                     std::memory_order_release);
    }

    // 2) Render the active voice into this buffer (if any).
    //    click_voice_pos_ >= click_len is our "inactive" state; we also treat
    //    very negative values (set at construction) as inactive implicitly
    //    because the while-loop below will advance pos without writing.
    if (click_voice_pos_ < click_len) {
      int32_t pos = click_voice_pos_;
      for (int32_t i = 0; i < num_frames; ++i) {
        if (pos >= 0 && pos < click_len) {
          out[i] += RenderClickSample(pos, click_len, sample_rate_);
        }
        ++pos;
      }
      click_voice_pos_ = pos;
    }

    // 3) Recording: for each track, if transport reached start_frame, flip
    //    armed -> recording and drain the needed number of mic samples from
    //    the ring into the track buffer.
    if (mic_ring_) {
      // If any track transitions armed->recording this pass, we must first
      // flush stale mic samples that have been accumulating in the ring
      // since engine Start(). Otherwise the recording would begin with
      // ancient audio instead of "now", offsetting everything in time.
      bool any_transition = false;
      for (auto& t : tracks_) {
        const auto state = static_cast<TrackState>(
            t.state.load(std::memory_order_acquire));
        if (state == TrackState::kArmed && t.start_frame < buf_end) {
          any_transition = true;
          break;
        }
      }
      if (any_transition) {
        mic_ring_->DiscardAll();
      }

      for (auto& t : tracks_) {
        int state_int = t.state.load(std::memory_order_acquire);
        const auto state = static_cast<TrackState>(state_int);
        if (state != TrackState::kArmed && state != TrackState::kRecording) {
          continue;
        }
        if (state == TrackState::kArmed) {
          if (t.start_frame >= buf_end) continue;  // not yet
          // Transport has reached (or passed — we begin immediately) the
          // start frame. Transition to recording.
          t.write_pos = 0;
          t.state.store(static_cast<int>(TrackState::kRecording),
                        std::memory_order_release);
        }
        // Pull up to min(remaining, num_frames) mic samples. We don't attempt
        // to align to the exact start_frame sub-buffer offset — latency and
        // the ring's "oldest-first" policy already dominate timing; the
        // resulting constant offset will be calibrated globally later.
        const int32_t remaining = t.length_samples - t.write_pos;
        if (remaining <= 0) {
          t.state.store(static_cast<int>(TrackState::kRecorded),
                        std::memory_order_release);
          continue;
        }
        const int32_t want =
            std::min(remaining, static_cast<int32_t>(mic_scratch_.size()));
        const int32_t got = mic_ring_->Read(mic_scratch_.data(), want);
        if (got > 0) {
          std::memcpy(t.buffer.data() + t.write_pos,
                      mic_scratch_.data(),
                      sizeof(float) * got);
          t.write_pos += got;
          if (t.write_pos >= t.length_samples) {
            // Auto-start playback on the exact sample that recording
            // completes. This is the key to loop-stays-in-time: playback
            // begins at t.start_frame + t.length_samples, which is ALWAYS
            // an integer multiple of samples_per_beat from t.start_frame,
            // so the loop's phase is locked to the metronome grid.
            //
            // We intentionally don't wait for a Dart-side startTrackPlayback
            // call — that would introduce JNI/Timer jitter (tens of ms) and
            // shift the loop relative to subsequent clicks.
            t.play_pos = 0;
            t.playing.store(true, std::memory_order_release);
            t.state.store(static_cast<int>(TrackState::kRecorded),
                          std::memory_order_release);
          }
        }
      }
    }

    // 4) Playback: for each track with playing=true, mix looped samples into
    //    out[]. play_pos wraps at length_samples for seamless looping.
    for (auto& t : tracks_) {
      if (!t.playing.load(std::memory_order_acquire)) continue;
      const int32_t len = t.length_samples;
      if (len <= 0) continue;  // nothing recorded yet
      int32_t pos = t.play_pos;
      if (pos >= len) pos = 0;  // defensive
      const float* src = t.buffer.data();
      for (int32_t i = 0; i < num_frames; ++i) {
        out[i] += src[pos];
        if (++pos >= len) pos = 0;
      }
      t.play_pos = pos;
    }

    // 5) Soft clamp. Summing multiple tracks + click can exceed [-1,1]. Hard
    //    clamp is ugly but cheap and prevents speaker-destroying transients;
    //    a proper limiter can come later if it turns out to matter.
    for (int32_t i = 0; i < num_frames; ++i) {
      const float s = out[i];
      out[i] = s > 1.0f ? 1.0f : (s < -1.0f ? -1.0f : s);
    }

    sample_counter_.fetch_add(num_frames, std::memory_order_relaxed);
  } else {
    // Input stream. Push mic samples into the ring for the output callback
    // to consume. Float, mono — 1 sample per frame.
    if (mic_ring_) {
      mic_ring_->Write(static_cast<const float*>(audio_data), num_frames);
    }
  }
  return oboe::DataCallbackResult::Continue;
}

void Engine::onErrorAfterClose(oboe::AudioStream* stream, oboe::Result error) {
  LOGW("Stream closed due to error: %s (direction=%d)",
       oboe::convertToText(error),
       static_cast<int>(stream->getDirection()));
}

void Engine::SetTempoBpm(double bpm) {
  if (bpm <= 0.0) return;
  const double spb = (60.0 / bpm) * static_cast<double>(sample_rate_);
  const int32_t spb_i =
      static_cast<int32_t>(std::max(1.0, std::round(spb)));
  samples_per_beat_.store(spb_i, std::memory_order_relaxed);
  LOGI("SetTempoBpm: bpm=%.2f samples_per_beat=%d", bpm, spb_i);
}

void Engine::StartMetronome() {
  metronome_audible_.store(true, std::memory_order_release);
  metronome_start_request_.store(true, std::memory_order_release);
  LOGI("StartMetronome requested");
}

void Engine::StopMetronome() {
  metronome_running_.store(false, std::memory_order_release);
  LOGI("StopMetronome");
}

void Engine::SetMetronomeAudible(bool audible) {
  metronome_audible_.store(audible, std::memory_order_release);
  LOGI("SetMetronomeAudible: %s", audible ? "true" : "false");
}

bool Engine::ArmRecording(int32_t track_id,
                          int64_t start_frame,
                          int32_t length_frames) {
  if (track_id < 0 || track_id >= kMaxTracks) return false;
  if (length_frames <= 0) return false;

  Track& t = tracks_[track_id];
  const int32_t cap = static_cast<int32_t>(t.buffer.size());
  if (cap == 0) {
    LOGW("ArmRecording before engine Start()");
    return false;
  }
  const int32_t clamped =
      length_frames > cap ? cap : length_frames;

  // Note: we write start_frame / length_samples / write_pos BEFORE publishing
  // the Armed state. The audio thread only looks at those fields once it
  // observes state == kArmed, so a release-store below is the synchronization
  // point. This is the standard "publish via atomic store" idiom.
  t.start_frame = start_frame;
  t.length_samples = clamped;
  t.write_pos = 0;
  t.state.store(static_cast<int>(TrackState::kArmed),
                std::memory_order_release);
  LOGI("ArmRecording: track=%d start=%lld length=%d",
       track_id,
       static_cast<long long>(start_frame),
       clamped);
  return true;
}

int32_t Engine::GetTrackState(int32_t track_id) const {
  if (track_id < 0 || track_id >= kMaxTracks) return -1;
  return tracks_[track_id].state.load(std::memory_order_acquire);
}

int32_t Engine::TrackRecordedSamples(int32_t track_id) const {
  if (track_id < 0 || track_id >= kMaxTracks) return 0;
  const Track& t = tracks_[track_id];
  const auto state =
      static_cast<stack_looper::TrackState>(
          t.state.load(std::memory_order_acquire));
  if (state == stack_looper::TrackState::kRecorded) return t.length_samples;
  if (state == stack_looper::TrackState::kRecording) return t.write_pos;
  return 0;
}

std::vector<float> Engine::TrackWaveformPeaks(int32_t track_id,
                                              int32_t bucket_count) const {
  if (track_id < 0 || track_id >= kMaxTracks || bucket_count <= 0) {
    return {};
  }

  const Track& t = tracks_[track_id];
  const auto state = static_cast<stack_looper::TrackState>(
      t.state.load(std::memory_order_acquire));
  const int32_t sample_count =
      state == stack_looper::TrackState::kRecording ? t.write_pos : t.length_samples;
  std::vector<float> peaks(static_cast<size_t>(bucket_count), 0.0f);
  if (sample_count <= 0) {
    return peaks;
  }

  const float* src = t.buffer.data();
  for (int32_t bucket = 0; bucket < bucket_count; ++bucket) {
    const int64_t start =
        (static_cast<int64_t>(bucket) * sample_count) / bucket_count;
    const int64_t end =
        (static_cast<int64_t>(bucket + 1) * sample_count) / bucket_count;
    float peak = 0.0f;
    for (int64_t i = start; i < end; ++i) {
      const float value = std::abs(src[i]);
      if (value > peak) peak = value;
    }
    peaks[static_cast<size_t>(bucket)] = peak;
  }
  return peaks;
}

void Engine::StartTrackPlayback(int32_t track_id) {
  if (track_id < 0 || track_id >= kMaxTracks) return;
  Track& t = tracks_[track_id];
  // Only meaningful for recorded tracks. We allow starting while still
  // recording — callback will just mix whatever is already written and loop
  // at length_samples once it's set.
  const auto state =
      static_cast<stack_looper::TrackState>(
          t.state.load(std::memory_order_acquire));
  if (state == stack_looper::TrackState::kEmpty) {
    LOGW("StartTrackPlayback on empty track %d", track_id);
    return;
  }
  // Reset play_pos from this thread is safe ONLY because playing is false
  // here; if it's already playing, we leave play_pos alone. If the caller
  // wants a restart-from-zero they should Stop first.
  if (!t.playing.load(std::memory_order_acquire)) {
    t.play_pos = 0;
  }
  t.playing.store(true, std::memory_order_release);
  LOGI("StartTrackPlayback: track=%d", track_id);
}

void Engine::StopTrackPlayback(int32_t track_id) {
  if (track_id < 0 || track_id >= kMaxTracks) return;
  tracks_[track_id].playing.store(false, std::memory_order_release);
  LOGI("StopTrackPlayback: track=%d", track_id);
}

bool Engine::IsTrackPlaying(int32_t track_id) const {
  if (track_id < 0 || track_id >= kMaxTracks) return false;
  return tracks_[track_id].playing.load(std::memory_order_acquire);
}

void Engine::ClearTrack(int32_t track_id) {
  if (track_id < 0 || track_id >= kMaxTracks) return;
  Track& t = tracks_[track_id];
  // Stop playback BEFORE clearing bookkeeping so the audio thread doesn't
  // briefly read inconsistent state. The audio thread only uses
  // length_samples / write_pos / play_pos when playing=true or state=armed/
  // recording, so clearing them after disabling both flags is safe.
  t.playing.store(false, std::memory_order_release);
  t.state.store(static_cast<int>(stack_looper::TrackState::kEmpty),
                std::memory_order_release);
  t.length_samples = 0;
  t.write_pos = 0;
  t.play_pos = 0;
  t.start_frame = 0;
  LOGI("ClearTrack: track=%d", track_id);
}

Engine& GetGlobalEngine() {
  static Engine engine;
  return engine;
}

}  // namespace stack_looper
