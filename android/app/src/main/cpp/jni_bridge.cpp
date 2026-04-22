#include <jni.h>
#include <string>

#include "engine.h"

namespace stack_looper {
Engine& GetGlobalEngine();
}

extern "C" {

// Java binding:
//   com.example.stack_looper.StackLooperAudio.nativeVersion()
JNIEXPORT jstring JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeVersion(
    JNIEnv* env, jclass /*clazz*/) {
  // Bumped to 0.2 now that there is a real engine behind this.
  return env->NewStringUTF("stack_looper_engine 0.2 (oboe)");
}

// Returns 0 on success, or an oboe::Result code cast to int on failure.
JNIEXPORT jint JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeStart(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jint>(stack_looper::GetGlobalEngine().Start());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeStop(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  stack_looper::GetGlobalEngine().Stop();
}

JNIEXPORT jint JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSampleRate(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jint>(stack_looper::GetGlobalEngine().SampleRate());
}

JNIEXPORT jboolean JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeIsRunning(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return stack_looper::GetGlobalEngine().IsRunning() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetTempoBpm(
    JNIEnv* /*env*/, jclass /*clazz*/, jdouble bpm) {
  stack_looper::GetGlobalEngine().SetTempoBpm(static_cast<double>(bpm));
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeStartMetronome(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  stack_looper::GetGlobalEngine().StartMetronome();
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeStopMetronome(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  stack_looper::GetGlobalEngine().StopMetronome();
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetMetronomeAudible(
    JNIEnv* /*env*/, jclass /*clazz*/, jboolean audible) {
  stack_looper::GetGlobalEngine().SetMetronomeAudible(audible == JNI_TRUE);
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetMasterOutputGainDb(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat db) {
  stack_looper::GetGlobalEngine().SetMasterOutputGainDb(static_cast<float>(db));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeMasterOutputGainDb(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().MasterOutputGainDb());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetLimiterCeilingDb(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat db) {
  stack_looper::GetGlobalEngine().SetLimiterCeilingDb(static_cast<float>(db));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeLimiterCeilingDb(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().LimiterCeilingDb());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetTrackOutputGainDb(
    JNIEnv* /*env*/, jclass /*clazz*/, jint track_id, jfloat db) {
  stack_looper::GetGlobalEngine().SetTrackOutputGainDb(
      static_cast<int32_t>(track_id), static_cast<float>(db));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeTrackOutputGainDb(
    JNIEnv* /*env*/, jclass /*clazz*/, jint track_id) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().TrackOutputGainDb(
      static_cast<int32_t>(track_id)));
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetTrackDelaySendEnabled(
    JNIEnv* /*env*/, jclass /*clazz*/, jint track_id, jboolean enabled) {
  stack_looper::GetGlobalEngine().SetTrackDelaySendEnabled(
      static_cast<int32_t>(track_id), enabled == JNI_TRUE);
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetTrackReverbSendEnabled(
    JNIEnv* /*env*/, jclass /*clazz*/, jint track_id, jboolean enabled) {
  stack_looper::GetGlobalEngine().SetTrackReverbSendEnabled(
      static_cast<int32_t>(track_id), enabled == JNI_TRUE);
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetHighPassHz(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat hz) {
  stack_looper::GetGlobalEngine().SetHighPassHz(static_cast<float>(hz));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeHighPassHz(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().HighPassHz());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetLowPassHz(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat hz) {
  stack_looper::GetGlobalEngine().SetLowPassHz(static_cast<float>(hz));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeLowPassHz(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().LowPassHz());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetEqLowDb(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat db) {
  stack_looper::GetGlobalEngine().SetEqLowDb(static_cast<float>(db));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeEqLowDb(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().EqLowDb());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetEqMidDb(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat db) {
  stack_looper::GetGlobalEngine().SetEqMidDb(static_cast<float>(db));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeEqMidDb(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().EqMidDb());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetEqHighDb(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat db) {
  stack_looper::GetGlobalEngine().SetEqHighDb(static_cast<float>(db));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeEqHighDb(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().EqHighDb());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetCompressorAmount(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat amount) {
  stack_looper::GetGlobalEngine().SetCompressorAmount(static_cast<float>(amount));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeCompressorAmount(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().CompressorAmount());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetDistortionAmount(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat amount) {
  stack_looper::GetGlobalEngine().SetDistortionAmount(static_cast<float>(amount));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeDistortionAmount(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().DistortionAmount());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetSaturationAmount(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat amount) {
  stack_looper::GetGlobalEngine().SetSaturationAmount(static_cast<float>(amount));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSaturationAmount(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().SaturationAmount());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetDelaySend(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat amount) {
  stack_looper::GetGlobalEngine().SetDelaySend(static_cast<float>(amount));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeDelaySend(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().DelaySend());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetDelayDivision(
    JNIEnv* /*env*/, jclass /*clazz*/, jint division) {
  stack_looper::GetGlobalEngine().SetDelayDivision(static_cast<int32_t>(division));
}

JNIEXPORT jint JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeDelayDivision(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jint>(stack_looper::GetGlobalEngine().DelayDivision());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetDelayFeel(
    JNIEnv* /*env*/, jclass /*clazz*/, jint feel) {
  stack_looper::GetGlobalEngine().SetDelayFeel(static_cast<int32_t>(feel));
}

JNIEXPORT jint JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeDelayFeel(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jint>(stack_looper::GetGlobalEngine().DelayFeel());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetReverbSend(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat amount) {
  stack_looper::GetGlobalEngine().SetReverbSend(static_cast<float>(amount));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeReverbSend(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().ReverbSend());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetReverbRoomSize(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat amount) {
  stack_looper::GetGlobalEngine().SetReverbRoomSize(static_cast<float>(amount));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeReverbRoomSize(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().ReverbRoomSize());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetDjFilterAmount(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat amount) {
  stack_looper::GetGlobalEngine().SetDjFilterAmount(static_cast<float>(amount));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeDjFilterAmount(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().DjFilterAmount());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetDjFilterResonance(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat amount) {
  stack_looper::GetGlobalEngine().SetDjFilterResonance(static_cast<float>(amount));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeDjFilterResonance(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().DjFilterResonance());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetBeatRepeatMix(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat amount) {
  stack_looper::GetGlobalEngine().SetBeatRepeatMix(static_cast<float>(amount));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeBeatRepeatMix(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().BeatRepeatMix());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetBeatRepeatDivision(
    JNIEnv* /*env*/, jclass /*clazz*/, jint division) {
  stack_looper::GetGlobalEngine().SetBeatRepeatDivision(static_cast<int32_t>(division));
}

JNIEXPORT jint JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeBeatRepeatDivision(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jint>(stack_looper::GetGlobalEngine().BeatRepeatDivision());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetTransGateAmount(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat amount) {
  stack_looper::GetGlobalEngine().SetTransGateAmount(static_cast<float>(amount));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeTransGateAmount(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().TransGateAmount());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetTransGateDivision(
    JNIEnv* /*env*/, jclass /*clazz*/, jint division) {
  stack_looper::GetGlobalEngine().SetTransGateDivision(static_cast<int32_t>(division));
}

JNIEXPORT jint JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeTransGateDivision(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jint>(stack_looper::GetGlobalEngine().TransGateDivision());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetNoiseRiserAmount(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat amount) {
  stack_looper::GetGlobalEngine().SetNoiseRiserAmount(static_cast<float>(amount));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeNoiseRiserAmount(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().NoiseRiserAmount());
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSetTapeStopAmount(
    JNIEnv* /*env*/, jclass /*clazz*/, jfloat amount) {
  stack_looper::GetGlobalEngine().SetTapeStopAmount(static_cast<float>(amount));
}

JNIEXPORT jfloat JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeTapeStopAmount(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jfloat>(stack_looper::GetGlobalEngine().TapeStopAmount());
}

JNIEXPORT jlong JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeCurrentFrame(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jlong>(stack_looper::GetGlobalEngine().CurrentFrame());
}

JNIEXPORT jint JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeSamplesPerBeat(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jint>(stack_looper::GetGlobalEngine().SamplesPerBeat());
}

JNIEXPORT jlong JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeCurrentBeat(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jlong>(stack_looper::GetGlobalEngine().CurrentBeat());
}

JNIEXPORT jlong JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeNextClickFrame(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jlong>(stack_looper::GetGlobalEngine().NextClickFrame());
}

JNIEXPORT jboolean JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeArmRecording(
    JNIEnv* /*env*/, jclass /*clazz*/,
    jint track_id, jlong start_frame, jint length_frames) {
  return stack_looper::GetGlobalEngine().ArmRecording(
             static_cast<int32_t>(track_id),
             static_cast<int64_t>(start_frame),
             static_cast<int32_t>(length_frames))
             ? JNI_TRUE
             : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeTrackState(
    JNIEnv* /*env*/, jclass /*clazz*/, jint track_id) {
  return static_cast<jint>(
      stack_looper::GetGlobalEngine().GetTrackState(
          static_cast<int32_t>(track_id)));
}

JNIEXPORT jint JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeTrackRecordedSamples(
    JNIEnv* /*env*/, jclass /*clazz*/, jint track_id) {
  return static_cast<jint>(
      stack_looper::GetGlobalEngine().TrackRecordedSamples(
          static_cast<int32_t>(track_id)));
}

JNIEXPORT jfloatArray JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeTrackWaveformPeaks(
    JNIEnv* env, jclass /*clazz*/, jint track_id, jint bucket_count) {
  const auto peaks = stack_looper::GetGlobalEngine().TrackWaveformPeaks(
      static_cast<int32_t>(track_id), static_cast<int32_t>(bucket_count));
  jfloatArray result = env->NewFloatArray(static_cast<jsize>(peaks.size()));
  if (result == nullptr || peaks.empty()) {
    return result;
  }
  env->SetFloatArrayRegion(
      result, 0, static_cast<jsize>(peaks.size()), peaks.data());
  return result;
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeStartTrackPlayback(
    JNIEnv* /*env*/, jclass /*clazz*/, jint track_id) {
  stack_looper::GetGlobalEngine().StartTrackPlayback(
      static_cast<int32_t>(track_id));
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeStopTrackPlayback(
    JNIEnv* /*env*/, jclass /*clazz*/, jint track_id) {
  stack_looper::GetGlobalEngine().StopTrackPlayback(
      static_cast<int32_t>(track_id));
}

JNIEXPORT jboolean JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeIsTrackPlaying(
    JNIEnv* /*env*/, jclass /*clazz*/, jint track_id) {
  return stack_looper::GetGlobalEngine().IsTrackPlaying(
             static_cast<int32_t>(track_id))
             ? JNI_TRUE
             : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_example_stack_1looper_StackLooperAudio_nativeClearTrack(
    JNIEnv* /*env*/, jclass /*clazz*/, jint track_id) {
  stack_looper::GetGlobalEngine().ClearTrack(static_cast<int32_t>(track_id));
}

}  // extern "C"
