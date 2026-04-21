abstract class AudioService {
  Future<void> initialize();
  Future<void> dispose();

  Future<void> startTrackRecording(int trackId, int barLength, int bpm);
  Future<void> stopTrackRecording(int trackId);

  Future<void> playTrack(int trackId, {required bool loop});
  Future<void> stopAll();
  Future<void> deleteTrack(int trackId);
}

class AudioServiceStub implements AudioService {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> startTrackRecording(int trackId, int barLength, int bpm) async {}

  @override
  Future<void> stopTrackRecording(int trackId) async {}

  @override
  Future<void> playTrack(int trackId, {required bool loop}) async {}

  @override
  Future<void> stopAll() async {}

  @override
  Future<void> deleteTrack(int trackId) async {}
}
