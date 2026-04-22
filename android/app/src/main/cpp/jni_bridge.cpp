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
