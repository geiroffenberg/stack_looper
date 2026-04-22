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

struct BiquadCoeffs {
  float b0 = 1.0f;
  float b1 = 0.0f;
  float b2 = 0.0f;
  float a1 = 0.0f;
  float a2 = 0.0f;
};

inline BiquadCoeffs MakeIdentity() {
  return {};
}

inline BiquadCoeffs MakeLowPass(float sample_rate, float hz, float q) {
  const float w0 = kTwoPi * hz / sample_rate;
  const float c = std::cos(w0);
  const float s = std::sin(w0);
  const float alpha = s / (2.0f * q);
  const float b0 = (1.0f - c) * 0.5f;
  const float b1 = 1.0f - c;
  const float b2 = (1.0f - c) * 0.5f;
  const float a0 = 1.0f + alpha;
  const float a1 = -2.0f * c;
  const float a2 = 1.0f - alpha;
  return {b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0};
}

inline BiquadCoeffs MakeHighPass(float sample_rate, float hz, float q) {
  const float w0 = kTwoPi * hz / sample_rate;
  const float c = std::cos(w0);
  const float s = std::sin(w0);
  const float alpha = s / (2.0f * q);
  const float b0 = (1.0f + c) * 0.5f;
  const float b1 = -(1.0f + c);
  const float b2 = (1.0f + c) * 0.5f;
  const float a0 = 1.0f + alpha;
  const float a1 = -2.0f * c;
  const float a2 = 1.0f - alpha;
  return {b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0};
}

inline BiquadCoeffs MakePeaking(float sample_rate, float hz, float q, float gain_db) {
  const float A = std::pow(10.0f, gain_db / 40.0f);
  const float w0 = kTwoPi * hz / sample_rate;
  const float c = std::cos(w0);
  const float s = std::sin(w0);
  const float alpha = s / (2.0f * q);
  const float b0 = 1.0f + alpha * A;
  const float b1 = -2.0f * c;
  const float b2 = 1.0f - alpha * A;
  const float a0 = 1.0f + alpha / A;
  const float a1 = -2.0f * c;
  const float a2 = 1.0f - alpha / A;
  return {b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0};
}

inline BiquadCoeffs MakeLowShelf(float sample_rate, float hz, float gain_db, float slope = 1.0f) {
  const float A = std::pow(10.0f, gain_db / 40.0f);
  const float w0 = kTwoPi * hz / sample_rate;
  const float c = std::cos(w0);
  const float s = std::sin(w0);
  const float alpha =
      s / 2.0f * std::sqrt((A + 1.0f / A) * (1.0f / slope - 1.0f) + 2.0f);
  const float two_sqrt_A_alpha = 2.0f * std::sqrt(A) * alpha;
  const float b0 = A * ((A + 1.0f) - (A - 1.0f) * c + two_sqrt_A_alpha);
  const float b1 = 2.0f * A * ((A - 1.0f) - (A + 1.0f) * c);
  const float b2 = A * ((A + 1.0f) - (A - 1.0f) * c - two_sqrt_A_alpha);
  const float a0 = (A + 1.0f) + (A - 1.0f) * c + two_sqrt_A_alpha;
  const float a1 = -2.0f * ((A - 1.0f) + (A + 1.0f) * c);
  const float a2 = (A + 1.0f) + (A - 1.0f) * c - two_sqrt_A_alpha;
  return {b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0};
}

inline BiquadCoeffs MakeHighShelf(float sample_rate, float hz, float gain_db, float slope = 1.0f) {
  const float A = std::pow(10.0f, gain_db / 40.0f);
  const float w0 = kTwoPi * hz / sample_rate;
  const float c = std::cos(w0);
  const float s = std::sin(w0);
  const float alpha =
      s / 2.0f * std::sqrt((A + 1.0f / A) * (1.0f / slope - 1.0f) + 2.0f);
  const float two_sqrt_A_alpha = 2.0f * std::sqrt(A) * alpha;
  const float b0 = A * ((A + 1.0f) + (A - 1.0f) * c + two_sqrt_A_alpha);
  const float b1 = -2.0f * A * ((A - 1.0f) + (A + 1.0f) * c);
  const float b2 = A * ((A + 1.0f) + (A - 1.0f) * c - two_sqrt_A_alpha);
  const float a0 = (A + 1.0f) - (A - 1.0f) * c + two_sqrt_A_alpha;
  const float a1 = 2.0f * ((A - 1.0f) - (A + 1.0f) * c);
  const float a2 = (A + 1.0f) - (A - 1.0f) * c - two_sqrt_A_alpha;
  return {b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0};
}

inline float ClampHz(float hz, float sample_rate) {
  return std::max(20.0f, std::min(hz, sample_rate * 0.45f));
}

inline float Clamp01(float value) {
  return std::max(0.0f, std::min(value, 1.0f));
}

inline float ClampSigned(float value) {
  return std::max(-1.0f, std::min(value, 1.0f));
}

inline int32_t NormalizeDivision(int32_t division) {
  switch (division) {
    case 2:
    case 4:
    case 8:
    case 16:
      return division;
    default:
      return 8;
  }
}

inline int32_t NormalizeDelayFeel(int32_t feel) {
  switch (feel) {
    case 0:
    case 1:
    case 2:
      return feel;
    default:
      return 0;
  }
}

inline float LogLerpHz(float min_hz, float max_hz, float t) {
  const float clamped = Clamp01(t);
  const float log_min = std::log(min_hz);
  const float log_max = std::log(max_hz);
  return std::exp(log_min + (log_max - log_min) * clamped);
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
  master_output_gain_smoothed_ =
      master_output_gain_target_.load(std::memory_order_relaxed);
  for (int i = 0; i < kMaxTracks; ++i) {
    track_output_gain_target_[i].store(1.0f, std::memory_order_release);
    track_output_gain_smoothed_[i] = 1.0f;
    track_delay_send_enabled_[i].store(true, std::memory_order_release);
    track_reverb_send_enabled_[i].store(true, std::memory_order_release);
  }
  for (int i = 0; i < 5; ++i) {
    biquad_b0_[i] = 1.0f;
    biquad_b1_[i] = 0.0f;
    biquad_b2_[i] = 0.0f;
    biquad_a1_[i] = 0.0f;
    biquad_a2_[i] = 0.0f;
    biquad_z1_[i] = 0.0f;
    biquad_z2_[i] = 0.0f;
  }
  dj_filter_b0_ = 1.0f;
  dj_filter_b1_ = 0.0f;
  dj_filter_b2_ = 0.0f;
  dj_filter_a1_ = 0.0f;
  dj_filter_a2_ = 0.0f;
  dj_filter_z1_ = 0.0f;
  dj_filter_z2_ = 0.0f;
  compressor_env_ = 0.0f;
  compressor_gain_ = 1.0f;
  delay_buffer_.assign(static_cast<size_t>(sample_rate_ * 2), 0.0f);
  delay_write_pos_ = 0;
  delay_send_scratch_.assign(4096, 0.0f);
  reverb_send_scratch_.assign(4096, 0.0f);
  reverb_buffers_[0].assign(static_cast<size_t>(std::max(1, sample_rate_ * 29 / 1000)), 0.0f);
  reverb_buffers_[1].assign(static_cast<size_t>(std::max(1, sample_rate_ * 37 / 1000)), 0.0f);
  reverb_buffers_[2].assign(static_cast<size_t>(std::max(1, sample_rate_ * 43 / 1000)), 0.0f);
  reverb_write_pos_[0] = 0;
  reverb_write_pos_[1] = 0;
  reverb_write_pos_[2] = 0;
  reverb_lowpass_state_ = 0.0f;
  perf_history_buffer_.assign(static_cast<size_t>(sample_rate_ * 4), 0.0f);
  perf_history_write_pos_ = 0;
  beat_repeat_active_ = false;
  beat_repeat_capture_start_ = 0;
  beat_repeat_capture_length_ = 0;
  beat_repeat_last_division_ = 8;
  beat_repeat_play_pos_ = 0;
  noise_state_ = 0x12345678u;
  noise_lowpass_state_ = 0.0f;
  tape_stop_buffer_.assign(static_cast<size_t>(sample_rate_ * 4), 0.0f);
  tape_stop_write_pos_ = 0;
  tape_stop_active_ = false;
  tape_stop_read_pos_ = 0.0f;
  tape_stop_lowpass_state_ = 0.0f;

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
    if (static_cast<int32_t>(delay_send_scratch_.size()) < num_frames) {
      delay_send_scratch_.assign(static_cast<size_t>(num_frames), 0.0f);
    }
    if (static_cast<int32_t>(reverb_send_scratch_.size()) < num_frames) {
      reverb_send_scratch_.assign(static_cast<size_t>(num_frames), 0.0f);
    }
    std::fill_n(delay_send_scratch_.data(), num_frames, 0.0f);
    std::fill_n(reverb_send_scratch_.data(), num_frames, 0.0f);

    for (auto& t : tracks_) {
      if (!t.playing.load(std::memory_order_acquire)) continue;
      const int32_t len = t.length_samples;
      if (len <= 0) continue;  // nothing recorded yet
      const int track_id = static_cast<int>(&t - &tracks_[0]);
      const float gain_target =
          track_output_gain_target_[track_id].load(std::memory_order_acquire);
      float gain = track_output_gain_smoothed_[track_id];
      constexpr float kTrackGainSmoothing = 0.0025f;
      const bool delay_send_enabled =
          track_delay_send_enabled_[track_id].load(std::memory_order_acquire);
      const bool reverb_send_enabled =
          track_reverb_send_enabled_[track_id].load(std::memory_order_acquire);
      int32_t pos = t.play_pos;
      if (pos >= len) pos = 0;  // defensive
      const float* src = t.buffer.data();
      for (int32_t i = 0; i < num_frames; ++i) {
        gain += (gain_target - gain) * kTrackGainSmoothing;
        const float sample = src[pos] * gain;
        out[i] += sample;
        if (delay_send_enabled) {
          delay_send_scratch_[i] += sample;
        }
        if (reverb_send_enabled) {
          reverb_send_scratch_[i] += sample;
        }
        if (++pos >= len) pos = 0;
      }
      t.play_pos = pos;
      track_output_gain_smoothed_[track_id] = gain;
    }

    // 5) Apply master output gain with smoothing to avoid zipper noise when
    //    UI sliders move. This is realtime-safe: one atomic read + a tiny
    //    one-pole per sample.
    const float gain_target =
        master_output_gain_target_.load(std::memory_order_acquire);
    float gain = master_output_gain_smoothed_;
    constexpr float kGainSmoothing = 0.0025f;
    for (int32_t i = 0; i < num_frames; ++i) {
      gain += (gain_target - gain) * kGainSmoothing;
      out[i] *= gain;
    }
    master_output_gain_smoothed_ = gain;

    // 6) Master FX filters/EQ (HPF -> LPF -> low shelf -> peaking mid ->
    //    high shelf). Coeffs are rebuilt per callback from atomic targets.
    const float hp_hz = ClampHz(
        high_pass_hz_.load(std::memory_order_acquire),
        static_cast<float>(sample_rate_));
    const float lp_hz = ClampHz(
        low_pass_hz_.load(std::memory_order_acquire),
        static_cast<float>(sample_rate_));
    const float eq_low_db = eq_low_db_.load(std::memory_order_acquire);
    const float eq_mid_db = eq_mid_db_.load(std::memory_order_acquire);
    const float eq_high_db = eq_high_db_.load(std::memory_order_acquire);

    const BiquadCoeffs c_hpf = MakeHighPass(static_cast<float>(sample_rate_), hp_hz, 0.707f);
    const BiquadCoeffs c_lpf = MakeLowPass(static_cast<float>(sample_rate_), lp_hz, 0.707f);
    const BiquadCoeffs c_low = MakeLowShelf(static_cast<float>(sample_rate_), 120.0f, eq_low_db);
    const BiquadCoeffs c_mid = MakePeaking(static_cast<float>(sample_rate_), 1000.0f, 1.0f, eq_mid_db);
    const BiquadCoeffs c_high = MakeHighShelf(static_cast<float>(sample_rate_), 8000.0f, eq_high_db);

    biquad_b0_[0] = c_hpf.b0; biquad_b1_[0] = c_hpf.b1; biquad_b2_[0] = c_hpf.b2;
    biquad_a1_[0] = c_hpf.a1; biquad_a2_[0] = c_hpf.a2;
    biquad_b0_[1] = c_lpf.b0; biquad_b1_[1] = c_lpf.b1; biquad_b2_[1] = c_lpf.b2;
    biquad_a1_[1] = c_lpf.a1; biquad_a2_[1] = c_lpf.a2;
    biquad_b0_[2] = c_low.b0; biquad_b1_[2] = c_low.b1; biquad_b2_[2] = c_low.b2;
    biquad_a1_[2] = c_low.a1; biquad_a2_[2] = c_low.a2;
    biquad_b0_[3] = c_mid.b0; biquad_b1_[3] = c_mid.b1; biquad_b2_[3] = c_mid.b2;
    biquad_a1_[3] = c_mid.a1; biquad_a2_[3] = c_mid.a2;
    biquad_b0_[4] = c_high.b0; biquad_b1_[4] = c_high.b1; biquad_b2_[4] = c_high.b2;
    biquad_a1_[4] = c_high.a1; biquad_a2_[4] = c_high.a2;

    for (int32_t i = 0; i < num_frames; ++i) {
      float x = out[i];
      for (int biq = 0; biq < 5; ++biq) {
        const float y = biquad_b0_[biq] * x + biquad_z1_[biq];
        biquad_z1_[biq] = biquad_b1_[biq] * x - biquad_a1_[biq] * y + biquad_z2_[biq];
        biquad_z2_[biq] = biquad_b2_[biq] * x - biquad_a2_[biq] * y;
        x = y;
      }
      out[i] = x;
    }

    // 7) DJ performance filter. This is separate from the master HP/LP pair:
    //    a single bipolar sweep where <0 is low-pass, >0 is high-pass.
    const float dj_filter_amount =
        ClampSigned(dj_filter_amount_.load(std::memory_order_acquire));
    const float dj_filter_resonance =
        Clamp01(dj_filter_resonance_.load(std::memory_order_acquire));
    if (std::fabs(dj_filter_amount) > 0.0001f) {
      const float q = 0.707f + dj_filter_resonance * 7.0f;
      const BiquadCoeffs c = dj_filter_amount < 0.0f
          ? MakeLowPass(
                static_cast<float>(sample_rate_),
                LogLerpHz(180.0f, 20000.0f, 1.0f - (-dj_filter_amount)),
                q)
          : MakeHighPass(
                static_cast<float>(sample_rate_),
                LogLerpHz(20.0f, 12000.0f, dj_filter_amount),
                q);
      dj_filter_b0_ = c.b0;
      dj_filter_b1_ = c.b1;
      dj_filter_b2_ = c.b2;
      dj_filter_a1_ = c.a1;
      dj_filter_a2_ = c.a2;
      for (int32_t i = 0; i < num_frames; ++i) {
        const float x = out[i];
        const float y = dj_filter_b0_ * x + dj_filter_z1_;
        dj_filter_z1_ = dj_filter_b1_ * x - dj_filter_a1_ * y + dj_filter_z2_;
        dj_filter_z2_ = dj_filter_b2_ * x - dj_filter_a2_ * y;
        out[i] = y;
      }
    } else {
      dj_filter_z1_ = 0.0f;
      dj_filter_z2_ = 0.0f;
    }

    // 8) Dynamics and color stage.
    const float compressor_amount =
        Clamp01(compressor_amount_.load(std::memory_order_acquire));
    const float distortion_amount =
        Clamp01(distortion_amount_.load(std::memory_order_acquire));
    const float saturation_amount =
        Clamp01(saturation_amount_.load(std::memory_order_acquire));
    if (compressor_amount > 0.0001f ||
        distortion_amount > 0.0001f ||
        saturation_amount > 0.0001f) {
      const float attack = 0.02f;
      const float release = 0.00012f;
      const float threshold_db = -8.0f - 28.0f * compressor_amount;
      const float ratio = 1.0f + compressor_amount * 19.0f;
      float env = compressor_env_;
      float comp_gain = compressor_gain_;
      const float dist_drive = 1.0f + distortion_amount * 24.0f;
      const float sat_drive = 1.0f + saturation_amount * 8.0f;
      const float sat_norm = std::tanh(sat_drive);

      for (int32_t i = 0; i < num_frames; ++i) {
        float x = out[i];

        if (compressor_amount > 0.0001f) {
          const float abs_x = std::fabs(x);
          const float coeff = abs_x > env ? attack : release;
          env += (abs_x - env) * coeff;
          const float level_db = 20.0f * std::log10(std::max(env, 0.000001f));
          const float over_db = level_db - threshold_db;
          float gain_db = 0.0f;
          if (over_db > 0.0f) {
            gain_db = -over_db * (1.0f - 1.0f / ratio);
          }
          const float target_gain = std::pow(10.0f, gain_db / 20.0f);
          comp_gain += (target_gain - comp_gain) * 0.06f;
          x *= comp_gain;
        }

        if (distortion_amount > 0.0001f) {
          const float driven = x * dist_drive;
          const float hard = std::max(-1.0f, std::min(driven, 1.0f));
          x = x * (1.0f - distortion_amount) + hard * distortion_amount;
        }

        if (saturation_amount > 0.0001f && sat_norm > 0.000001f) {
          const float soft = std::tanh(x * sat_drive) / sat_norm;
          x = x * (1.0f - saturation_amount) + soft * saturation_amount;
        }

        out[i] = x;
      }

      compressor_env_ = env;
      compressor_gain_ = comp_gain;
    }

    // 9) Performance rhythm/gesture FX.
    const float beat_repeat_mix =
        Clamp01(beat_repeat_mix_.load(std::memory_order_acquire));
    const int32_t beat_repeat_division =
        NormalizeDivision(beat_repeat_division_.load(std::memory_order_acquire));
    const float trans_gate_amount =
        Clamp01(trans_gate_amount_.load(std::memory_order_acquire));
    const int32_t trans_gate_division =
        NormalizeDivision(trans_gate_division_.load(std::memory_order_acquire));
    const float noise_riser_amount =
        Clamp01(noise_riser_amount_.load(std::memory_order_acquire));
    const float tape_stop_amount =
        Clamp01(tape_stop_amount_.load(std::memory_order_acquire));

    int32_t history_write = perf_history_write_pos_;
    const int32_t history_len = static_cast<int32_t>(perf_history_buffer_.size());
    bool repeat_active = beat_repeat_active_;
    int32_t repeat_capture_start = beat_repeat_capture_start_;
    int32_t repeat_capture_length = beat_repeat_capture_length_;
    int32_t repeat_last_division = beat_repeat_last_division_;
    int32_t repeat_play_pos = beat_repeat_play_pos_;
    uint32_t noise_state = noise_state_;
    float noise_lp = noise_lowpass_state_;
    int32_t tape_write = tape_stop_write_pos_;
    const int32_t tape_len = static_cast<int32_t>(tape_stop_buffer_.size());
    bool tape_active = tape_stop_active_;
    float tape_read = tape_stop_read_pos_;
    float tape_lp = tape_stop_lowpass_state_;

    const int32_t repeat_length =
        std::max(1, std::min(history_len - 1, (spb * 4) / beat_repeat_division));
    const int32_t gate_length =
        std::max(1, (spb * 4) / trans_gate_division);

    for (int32_t i = 0; i < num_frames; ++i) {
      float x = out[i];

      if (history_len > 0) {
        perf_history_buffer_[history_write] = x;
        if (++history_write >= history_len) history_write = 0;
      }

      if (beat_repeat_mix > 0.0001f && history_len > 1) {
        if (!repeat_active || repeat_last_division != beat_repeat_division ||
            repeat_capture_length != repeat_length) {
          repeat_active = true;
          repeat_capture_length = repeat_length;
          repeat_capture_start = history_write - repeat_capture_length;
          while (repeat_capture_start < 0) repeat_capture_start += history_len;
          repeat_last_division = beat_repeat_division;
          repeat_play_pos = 0;
        }
        const int32_t repeat_index =
            (repeat_capture_start + repeat_play_pos) % history_len;
        const float repeated = perf_history_buffer_[repeat_index];
        x = x * (1.0f - beat_repeat_mix) + repeated * beat_repeat_mix;
        ++repeat_play_pos;
        if (repeat_play_pos >= repeat_capture_length) repeat_play_pos = 0;
      } else {
        repeat_active = false;
        repeat_play_pos = 0;
      }

      if (trans_gate_amount > 0.0001f) {
        const int64_t gate_frame = buf_start + i;
        const int32_t gate_phase = static_cast<int32_t>(gate_frame % gate_length);
        const float gate_norm = static_cast<float>(gate_phase) /
            static_cast<float>(std::max(1, gate_length - 1));
        const float gate_value = gate_norm < 0.52f ? 1.0f : 0.08f;
        const float gate_mix = (1.0f - trans_gate_amount) +
            gate_value * trans_gate_amount;
        x *= gate_mix;
      }

      if (noise_riser_amount > 0.0001f) {
        noise_state = noise_state * 1664525u + 1013904223u;
        const float white =
            (static_cast<float>((noise_state >> 8) & 0x00FFFFFFu) /
                8388607.5f) - 1.0f;
        noise_lp += (white - noise_lp) * 0.02f;
        const float airy = white - noise_lp;
        x += airy * noise_riser_amount * noise_riser_amount * 0.4f;
      }

      if (tape_len > 1) {
        tape_stop_buffer_[tape_write] = x;
        if (tape_stop_amount > 0.0001f) {
          if (!tape_active) {
            tape_active = true;
            tape_read = static_cast<float>((tape_write - 1 + tape_len) % tape_len);
            tape_lp = x;
          }
          const int32_t read0 = static_cast<int32_t>(tape_read) % tape_len;
          const int32_t read1 = (read0 + 1) % tape_len;
          const float frac = tape_read - std::floor(tape_read);
          const float slowed = tape_stop_buffer_[read0] +
              (tape_stop_buffer_[read1] - tape_stop_buffer_[read0]) * frac;
          const float speed = std::max(0.03f, 1.0f - tape_stop_amount * 0.97f);
          tape_read += speed;
          while (tape_read >= tape_len) tape_read -= tape_len;
          tape_lp += (slowed - tape_lp) * (0.24f - tape_stop_amount * 0.20f);
          x = x * (1.0f - tape_stop_amount) + tape_lp * tape_stop_amount;
        } else {
          tape_active = false;
        }
        if (++tape_write >= tape_len) tape_write = 0;
      }

      out[i] = x;
    }

    perf_history_write_pos_ = history_write;
    beat_repeat_active_ = repeat_active;
    beat_repeat_capture_start_ = repeat_capture_start;
    beat_repeat_capture_length_ = repeat_capture_length;
    beat_repeat_last_division_ = repeat_last_division;
    beat_repeat_play_pos_ = repeat_play_pos;
    noise_state_ = noise_state;
    noise_lowpass_state_ = noise_lp;
    tape_stop_write_pos_ = tape_write;
    tape_stop_active_ = tape_active;
    tape_stop_read_pos_ = tape_read;
    tape_stop_lowpass_state_ = tape_lp;

    // 10) Time FX sends: tempo-agnostic mono delay + compact feedback reverb.
    const float delay_send =
        Clamp01(delay_send_.load(std::memory_order_acquire));
    const int32_t delay_division =
      NormalizeDivision(delay_division_.load(std::memory_order_acquire));
    const int32_t delay_feel =
      NormalizeDelayFeel(delay_feel_.load(std::memory_order_acquire));
    const float reverb_send =
        Clamp01(reverb_send_.load(std::memory_order_acquire));
    const float reverb_room_size =
        Clamp01(reverb_room_size_.load(std::memory_order_acquire));
    if (delay_send > 0.0001f || reverb_send > 0.0001f) {
      if (!delay_buffer_.empty()) {
        const int32_t delay_len = static_cast<int32_t>(delay_buffer_.size());
        const float base_delay_samples =
          static_cast<float>(std::max(1, (spb * 4) / delay_division));
        const float feel_multiplier = delay_feel == 1
          ? 1.5f
          : (delay_feel == 2 ? (2.0f / 3.0f) : 1.0f);
        const int32_t delay_samples = std::max(
          1,
          std::min(
            delay_len - 1,
            static_cast<int32_t>(std::round(base_delay_samples * feel_multiplier))));
        int32_t delay_write = delay_write_pos_;

        const float room_scale = 0.72f + reverb_room_size * 0.56f;
        const std::array<float, 3> reverb_feedback{
          std::min(0.965f, 0.78f + reverb_room_size * 0.15f),
          std::min(0.972f, 0.81f + reverb_room_size * 0.14f),
          std::min(0.958f, 0.76f + reverb_room_size * 0.16f),
        };
        auto reverb_positions = reverb_write_pos_;
        float rev_lp = reverb_lowpass_state_;
        const int32_t reverb_pre_delay =
          std::max(
              1,
              std::min(
                  delay_len - 1,
                  static_cast<int32_t>(sample_rate_ * (0.018f + reverb_room_size * 0.060f))));

        for (int32_t i = 0; i < num_frames; ++i) {
          float x = out[i];
          const float delay_in = delay_send_scratch_[i];
          const float reverb_source = reverb_send_scratch_[i];
          const int32_t read =
              (delay_write - delay_samples + delay_len) % delay_len;
          const float tap = delay_buffer_[read];
          delay_buffer_[delay_write] = delay_in + (delay_send > 0.0001f ? tap * 0.35f : 0.0f);

          if (delay_send > 0.0001f) {
            x += tap * delay_send * 0.55f;
          }

          if (reverb_send > 0.0001f) {
            const int32_t pre_read =
                (delay_write - reverb_pre_delay + delay_len) % delay_len;
            const float rev_in = reverb_source + delay_buffer_[pre_read] * 0.35f;
            float rev_wet = 0.0f;
            for (int lane = 0; lane < 3; ++lane) {
              auto& buf = reverb_buffers_[lane];
              if (buf.empty()) continue;
              const int32_t usable_len = std::max(
                  1,
                  std::min(
                      static_cast<int32_t>(buf.size()) - 1,
                      static_cast<int32_t>(buf.size() * room_scale)));
              int32_t pos = reverb_positions[lane];
              if (pos >= usable_len) pos = 0;
              const float tap = buf[pos];
              rev_wet += tap;
              buf[pos] = rev_in + tap * reverb_feedback[lane];
              ++pos;
              if (pos >= usable_len) pos = 0;
              reverb_positions[lane] = pos;
            }
            rev_lp += (rev_wet - rev_lp) * (0.07f - reverb_room_size * 0.04f);
            x += rev_lp * reverb_send * (0.34f + reverb_room_size * 0.28f);
          }

          if (++delay_write >= delay_len) delay_write = 0;

          out[i] = x;
        }

        delay_write_pos_ = delay_write;
        reverb_write_pos_ = reverb_positions;
        reverb_lowpass_state_ = rev_lp;
      }
    }

    // 11) Master limiter: hard-limits to the configured
    //    ceiling in linear amplitude. This is intentionally simple and
    //    realtime-safe; we can replace it with lookahead later.
    const float limiter =
        limiter_ceiling_linear_.load(std::memory_order_acquire);
    for (int32_t i = 0; i < num_frames; ++i) {
      const float s = out[i];
      out[i] = s > limiter ? limiter : (s < -limiter ? -limiter : s);
    }

    // 12) Final safety clamp. Summing multiple tracks + click can exceed
    //    [-1,1] if misconfigured; this keeps output bounded.
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

void Engine::SetMasterOutputGainDb(float db) {
  const float clamped = std::max(-24.0f, std::min(db, 12.0f));
  const float linear = std::pow(10.0f, clamped / 20.0f);
  master_output_gain_target_.store(linear, std::memory_order_release);
  LOGI("SetMasterOutputGainDb: db=%.2f linear=%.4f", clamped, linear);
}

float Engine::MasterOutputGainDb() const {
  const float linear =
      master_output_gain_target_.load(std::memory_order_acquire);
  const float safe = std::max(linear, 0.000001f);
  return 20.0f * std::log10(safe);
}

void Engine::SetLimiterCeilingDb(float db) {
  const float clamped = std::max(-24.0f, std::min(db, -0.1f));
  const float linear = std::pow(10.0f, clamped / 20.0f);
  limiter_ceiling_linear_.store(linear, std::memory_order_release);
  LOGI("SetLimiterCeilingDb: db=%.2f linear=%.4f", clamped, linear);
}

float Engine::LimiterCeilingDb() const {
  const float linear =
      limiter_ceiling_linear_.load(std::memory_order_acquire);
  const float safe = std::max(linear, 0.000001f);
  return 20.0f * std::log10(safe);
}

void Engine::SetTrackOutputGainDb(int32_t track_id, float db) {
  if (track_id < 0 || track_id >= kMaxTracks) return;
  const float clamped = std::max(-60.0f, std::min(db, 12.0f));
  const float linear = std::pow(10.0f, clamped / 20.0f);
  track_output_gain_target_[track_id].store(linear, std::memory_order_release);
  LOGI("SetTrackOutputGainDb: track=%d db=%.2f linear=%.4f",
       track_id,
       clamped,
       linear);
}

float Engine::TrackOutputGainDb(int32_t track_id) const {
  if (track_id < 0 || track_id >= kMaxTracks) return 0.0f;
  const float linear =
      track_output_gain_target_[track_id].load(std::memory_order_acquire);
  const float safe = std::max(linear, 0.000001f);
  return 20.0f * std::log10(safe);
}

void Engine::SetTrackDelaySendEnabled(int32_t track_id, bool enabled) {
  if (track_id < 0 || track_id >= kMaxTracks) return;
  track_delay_send_enabled_[track_id].store(enabled, std::memory_order_release);
  LOGI("SetTrackDelaySendEnabled: track=%d enabled=%s",
       track_id,
       enabled ? "true" : "false");
}

bool Engine::TrackDelaySendEnabled(int32_t track_id) const {
  if (track_id < 0 || track_id >= kMaxTracks) return true;
  return track_delay_send_enabled_[track_id].load(std::memory_order_acquire);
}

void Engine::SetTrackReverbSendEnabled(int32_t track_id, bool enabled) {
  if (track_id < 0 || track_id >= kMaxTracks) return;
  track_reverb_send_enabled_[track_id].store(enabled, std::memory_order_release);
  LOGI("SetTrackReverbSendEnabled: track=%d enabled=%s",
       track_id,
       enabled ? "true" : "false");
}

bool Engine::TrackReverbSendEnabled(int32_t track_id) const {
  if (track_id < 0 || track_id >= kMaxTracks) return true;
  return track_reverb_send_enabled_[track_id].load(std::memory_order_acquire);
}

void Engine::SetHighPassHz(float hz) {
  const float clamped = ClampHz(hz, static_cast<float>(sample_rate_));
  high_pass_hz_.store(clamped, std::memory_order_release);
  LOGI("SetHighPassHz: %.1f", clamped);
}

float Engine::HighPassHz() const {
  return high_pass_hz_.load(std::memory_order_acquire);
}

void Engine::SetLowPassHz(float hz) {
  const float clamped = ClampHz(hz, static_cast<float>(sample_rate_));
  low_pass_hz_.store(clamped, std::memory_order_release);
  LOGI("SetLowPassHz: %.1f", clamped);
}

float Engine::LowPassHz() const {
  return low_pass_hz_.load(std::memory_order_acquire);
}

void Engine::SetEqLowDb(float db) {
  const float clamped = std::max(-24.0f, std::min(db, 12.0f));
  eq_low_db_.store(clamped, std::memory_order_release);
  LOGI("SetEqLowDb: %.2f", clamped);
}

float Engine::EqLowDb() const {
  return eq_low_db_.load(std::memory_order_acquire);
}

void Engine::SetEqMidDb(float db) {
  const float clamped = std::max(-24.0f, std::min(db, 12.0f));
  eq_mid_db_.store(clamped, std::memory_order_release);
  LOGI("SetEqMidDb: %.2f", clamped);
}

float Engine::EqMidDb() const {
  return eq_mid_db_.load(std::memory_order_acquire);
}

void Engine::SetEqHighDb(float db) {
  const float clamped = std::max(-24.0f, std::min(db, 12.0f));
  eq_high_db_.store(clamped, std::memory_order_release);
  LOGI("SetEqHighDb: %.2f", clamped);
}

float Engine::EqHighDb() const {
  return eq_high_db_.load(std::memory_order_acquire);
}

void Engine::SetCompressorAmount(float amount) {
  const float clamped = Clamp01(amount);
  compressor_amount_.store(clamped, std::memory_order_release);
  LOGI("SetCompressorAmount: %.3f", clamped);
}

float Engine::CompressorAmount() const {
  return compressor_amount_.load(std::memory_order_acquire);
}

void Engine::SetDistortionAmount(float amount) {
  const float clamped = Clamp01(amount);
  distortion_amount_.store(clamped, std::memory_order_release);
  LOGI("SetDistortionAmount: %.3f", clamped);
}

float Engine::DistortionAmount() const {
  return distortion_amount_.load(std::memory_order_acquire);
}

void Engine::SetSaturationAmount(float amount) {
  const float clamped = Clamp01(amount);
  saturation_amount_.store(clamped, std::memory_order_release);
  LOGI("SetSaturationAmount: %.3f", clamped);
}

float Engine::SaturationAmount() const {
  return saturation_amount_.load(std::memory_order_acquire);
}

void Engine::SetDelaySend(float amount) {
  const float clamped = Clamp01(amount);
  delay_send_.store(clamped, std::memory_order_release);
  LOGI("SetDelaySend: %.3f", clamped);
}

float Engine::DelaySend() const {
  return delay_send_.load(std::memory_order_acquire);
}

void Engine::SetDelayDivision(int32_t division) {
  const int32_t normalized = NormalizeDivision(division);
  delay_division_.store(normalized, std::memory_order_release);
  LOGI("SetDelayDivision: %d", normalized);
}

int32_t Engine::DelayDivision() const {
  return delay_division_.load(std::memory_order_acquire);
}

void Engine::SetDelayFeel(int32_t feel) {
  const int32_t normalized = NormalizeDelayFeel(feel);
  delay_feel_.store(normalized, std::memory_order_release);
  LOGI("SetDelayFeel: %d", normalized);
}

int32_t Engine::DelayFeel() const {
  return delay_feel_.load(std::memory_order_acquire);
}

void Engine::SetReverbSend(float amount) {
  const float clamped = Clamp01(amount);
  reverb_send_.store(clamped, std::memory_order_release);
  LOGI("SetReverbSend: %.3f", clamped);
}

float Engine::ReverbSend() const {
  return reverb_send_.load(std::memory_order_acquire);
}

void Engine::SetReverbRoomSize(float amount) {
  const float clamped = Clamp01(amount);
  reverb_room_size_.store(clamped, std::memory_order_release);
  LOGI("SetReverbRoomSize: %.3f", clamped);
}

float Engine::ReverbRoomSize() const {
  return reverb_room_size_.load(std::memory_order_acquire);
}

void Engine::SetDjFilterAmount(float amount) {
  const float clamped = ClampSigned(amount);
  dj_filter_amount_.store(clamped, std::memory_order_release);
  LOGI("SetDjFilterAmount: %.3f", clamped);
}

float Engine::DjFilterAmount() const {
  return dj_filter_amount_.load(std::memory_order_acquire);
}

void Engine::SetDjFilterResonance(float amount) {
  const float clamped = Clamp01(amount);
  dj_filter_resonance_.store(clamped, std::memory_order_release);
  LOGI("SetDjFilterResonance: %.3f", clamped);
}

float Engine::DjFilterResonance() const {
  return dj_filter_resonance_.load(std::memory_order_acquire);
}

void Engine::SetBeatRepeatMix(float amount) {
  const float clamped = Clamp01(amount);
  beat_repeat_mix_.store(clamped, std::memory_order_release);
  LOGI("SetBeatRepeatMix: %.3f", clamped);
}

float Engine::BeatRepeatMix() const {
  return beat_repeat_mix_.load(std::memory_order_acquire);
}

void Engine::SetBeatRepeatDivision(int32_t division) {
  const int32_t normalized = NormalizeDivision(division);
  beat_repeat_division_.store(normalized, std::memory_order_release);
  LOGI("SetBeatRepeatDivision: %d", normalized);
}

int32_t Engine::BeatRepeatDivision() const {
  return beat_repeat_division_.load(std::memory_order_acquire);
}

void Engine::SetTransGateAmount(float amount) {
  const float clamped = Clamp01(amount);
  trans_gate_amount_.store(clamped, std::memory_order_release);
  LOGI("SetTransGateAmount: %.3f", clamped);
}

float Engine::TransGateAmount() const {
  return trans_gate_amount_.load(std::memory_order_acquire);
}

void Engine::SetTransGateDivision(int32_t division) {
  const int32_t normalized = NormalizeDivision(division);
  trans_gate_division_.store(normalized, std::memory_order_release);
  LOGI("SetTransGateDivision: %d", normalized);
}

int32_t Engine::TransGateDivision() const {
  return trans_gate_division_.load(std::memory_order_acquire);
}

void Engine::SetNoiseRiserAmount(float amount) {
  const float clamped = Clamp01(amount);
  noise_riser_amount_.store(clamped, std::memory_order_release);
  LOGI("SetNoiseRiserAmount: %.3f", clamped);
}

float Engine::NoiseRiserAmount() const {
  return noise_riser_amount_.load(std::memory_order_acquire);
}

void Engine::SetTapeStopAmount(float amount) {
  const float clamped = Clamp01(amount);
  tape_stop_amount_.store(clamped, std::memory_order_release);
  LOGI("SetTapeStopAmount: %.3f", clamped);
}

float Engine::TapeStopAmount() const {
  return tape_stop_amount_.load(std::memory_order_acquire);
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
