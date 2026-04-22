/// Audio service interface used by [LooperProvider].
///
/// As of chunk 9, the only real implementation is
/// [NativeAudioService] in `native_audio_service.dart`, which is backed by
/// the C++ Oboe engine. The old Dart stack (record/just_audio/flutter_soloud)
/// was removed because it could not reach sample accuracy — three separate
/// clocks (MediaRecorder, ExoPlayer, SoLoud) drifted against each other.
abstract class AudioService {
  Future<void> initialize();
  Future<void> dispose();

  Future<void> startTrackRecording(int trackId, int barLength, int bpm);
  Future<void> stopTrackRecording(int trackId);

  Future<void> playTrack(int trackId, {required bool loop});
  Future<void> stopAll();
  Future<void> deleteTrack(int trackId);

  Future<bool> hasRecordedAudio(int trackId);

  Future<void> playClick();
}

/// No-op stub. Used by tests and as a safe default when the native engine
/// is unavailable (e.g. running widget tests outside an emulator).
class AudioServiceStub extends AudioService {
  final Set<int> _recorded = <int>{};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> startTrackRecording(int trackId, int barLength, int bpm) async {
    _recorded.add(trackId);
  }

  @override
  Future<void> stopTrackRecording(int trackId) async {}

  @override
  Future<void> playTrack(int trackId, {required bool loop}) async {}

  @override
  Future<void> stopAll() async {}

  @override
  Future<void> deleteTrack(int trackId) async {
    _recorded.remove(trackId);
  }

  @override
  Future<bool> hasRecordedAudio(int trackId) async => _recorded.contains(trackId);

  @override
  Future<void> playClick() async {}
}
