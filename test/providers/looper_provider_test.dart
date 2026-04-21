import 'package:flutter_test/flutter_test.dart';
import 'package:stack_looper/providers/looper_provider.dart';
import 'package:stack_looper/models/looper_state.dart';
import 'package:stack_looper/services/audio_service.dart';

class _FakeAudioService implements AudioService {
  @override
  Future<void> deleteTrack(int trackId) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> playTrack(int trackId, {required bool loop}) async {}

  @override
  Future<void> startTrackRecording(int trackId, int barLength, int bpm) async {}

  @override
  Future<void> stopAll() async {}

  @override
  Future<void> stopTrackRecording(int trackId) async {}
}

void main() {
  test('record toggle keeps playback running until play stops all', () async {
    final provider = LooperProvider(audioService: _FakeAudioService());

    await provider.startRecordingSession();
    expect(provider.state.transportState, TransportState.recording);

    await provider.startRecordingSession();
    expect(provider.state.transportState, TransportState.playing);

    await provider.playAll();
    expect(provider.state.transportState, TransportState.stopped);
  });

  test('play while recording stops both recording and playback', () async {
    final provider = LooperProvider(audioService: _FakeAudioService());

    await provider.startRecordingSession();
    expect(provider.state.transportState, TransportState.recording);

    await provider.playAll();
    expect(provider.state.transportState, TransportState.stopped);
  });

  test('visual bar divider count switches to 8 when any track is 8 bars', () {
    final provider = LooperProvider(audioService: _FakeAudioService());

    expect(provider.visualBarDividers, 4);

    provider.setTrackBarLength(0, 8);
    expect(provider.visualBarDividers, 8);
  });
}
