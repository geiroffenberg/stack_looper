import 'audio_service.dart';
import 'native_audio_engine.dart';
import '../constants/app_constants.dart';

/// [AudioService] implementation backed entirely by the native Oboe engine.
///
/// This is a drop-in replacement for [AudioServiceImpl]: same interface, but
/// the click, mic capture, recording, and playback all live in C++ and share
/// a single sample clock. That eliminates the three-independent-clocks
/// problem that caused the sloppy timing in the Dart/record/just_audio/soloud
/// stack.
///
/// Note: the existing [AudioService] interface is call-per-click style
/// (LooperProvider ticks and calls [playClick] on each beat). The native
/// engine schedules clicks sample-accurately on its own, so [playClick] here
/// is a no-op — chunk 9 will rewrite LooperProvider to let the native engine
/// drive timing instead of Dart timers.
class NativeAudioService extends AudioService {
  NativeAudioService({NativeAudioEngine? engine})
    : _engine = engine ?? NativeAudioEngine();

  final NativeAudioEngine _engine;

  NativeAudioEngine get engine => _engine;

  // Per-track state tracked on the Dart side. [_hasRecording] is a fast-path
  // cache so [hasRecordedAudio] doesn't need to round-trip to native on every
  // UI rebuild.
  final Set<int> _hasRecording = <int>{};

  // Cached samples-per-beat at the current tempo. Updated by
  // [startTrackRecording] which knows the bpm.
  int _samplesPerBeat = 0;

  @override
  Future<void> initialize() async {
    await _engine.start();
    // Tempo is set per-recording by LooperProvider; default 120 so the click
    // is meaningful on first boot.
    await _engine.setTempoBpm(120.0);
    _samplesPerBeat = await _engine.samplesPerBeat();
  }

  @override
  Future<void> dispose() async {
    await _engine.stopMetronome();
    await _engine.stop();
    _hasRecording.clear();
  }

  /// Updates the native tempo. Not part of [AudioService] — chunk 9 uses this
  /// directly from LooperProvider when the user changes bpm.
  Future<void> setTempoBpm(double bpm) async {
    await _engine.setTempoBpm(bpm);
    _samplesPerBeat = await _engine.samplesPerBeat();
  }

  /// Starts the native metronome. See note on [playClick] for why this lives
  /// as an explicit method rather than per-click calls.
  Future<void> startMetronome() => _engine.startMetronome();
  Future<void> stopMetronome() => _engine.stopMetronome();
  Future<void> setMetronomeAudible(bool audible) =>
      _engine.setMetronomeAudible(audible);

  Future<void> setMasterOutputGainDb(double db) =>
      _engine.setMasterOutputGainDb(db);

  Future<void> setLimiterCeilingDb(double db) =>
      _engine.setLimiterCeilingDb(db);

  Future<void> setHighPassHz(double hz) => _engine.setHighPassHz(hz);
  Future<void> setLowPassHz(double hz) => _engine.setLowPassHz(hz);
  Future<void> setEqLowDb(double db) => _engine.setEqLowDb(db);
  Future<void> setEqMidDb(double db) => _engine.setEqMidDb(db);
  Future<void> setEqHighDb(double db) => _engine.setEqHighDb(db);
  Future<void> setCompressorAmount(double amount) =>
      _engine.setCompressorAmount(amount);
  Future<void> setSaturationAmount(double amount) =>
      _engine.setSaturationAmount(amount);
  Future<void> setDelayDivision(int division) =>
      _engine.setDelayDivision(division);
  Future<void> setDelayFeel(int feel) => _engine.setDelayFeel(feel);
  Future<void> setDelayFeedback(double amount) =>
      _engine.setDelayFeedback(amount);
  Future<void> setDelayInput(double amount) => _engine.setDelayInput(amount);
  Future<void> setReverbRoomSize(double amount) =>
      _engine.setReverbRoomSize(amount);
  Future<void> setReverbDamping(double amount) =>
      _engine.setReverbDamping(amount);

  Future<void> setTrackOutputGainDb({
    required int trackId,
    required double db,
  }) => _engine.setTrackOutputGainDb(trackId: trackId, db: db);

  Future<void> setTrackDelaySendLevel({
    required int trackId,
    required double level,
  }) => _engine.setTrackDelaySendLevel(trackId: trackId, level: level);

  Future<void> setTrackReverbSendLevel({
    required int trackId,
    required double level,
  }) => _engine.setTrackReverbSendLevel(trackId: trackId, level: level);

  Future<List<double>> trackWaveformPeaks({
    required int trackId,
    required int bucketCount,
  }) => _engine.trackWaveformPeaks(trackId: trackId, bucketCount: bucketCount);

  /// Native beat stream — UI can listen to this for count-in flashes and
  /// playhead animation.
  Stream<int> get beatStream => _engine.beatStream;

  @override
  Future<void> startTrackRecording(int trackId, int barLength, int bpm) async {
    // Sync tempo in case the UI changed bpm since init.
    await _engine.setTempoBpm(bpm.toDouble());
    _samplesPerBeat = await _engine.samplesPerBeat();

    final lengthFrames = _samplesPerBeat * barLength;
    // Start "now" — LooperProvider handles the count-in at the Dart level
    // today. Chunk 9 will move count-in into the native engine so recording
    // can be scheduled exactly on a bar boundary.
    final startFrame = await _engine.currentFrame();
    await _engine.armRecording(
      trackId: trackId,
      startFrame: startFrame,
      lengthFrames: lengthFrames,
    );
    _hasRecording.add(trackId);
  }

  @override
  Future<void> stopTrackRecording(int trackId) async {
    // Native recording auto-stops after lengthFrames. This method remains for
    // API compatibility; there's no premature-stop mechanism yet.
  }

  @override
  Future<void> playTrack(int trackId, {required bool loop}) async {
    // Native engine always loops; the flag is accepted for interface parity.
    await _engine.startTrackPlayback(trackId);
  }

  @override
  Future<void> stopAll() async {
    for (var i = 0; i < AppConstants.maxTracks; i++) {
      await _engine.stopTrackPlayback(i);
    }
  }

  @override
  Future<void> deleteTrack(int trackId) async {
    await _engine.clearTrack(trackId);
    _hasRecording.remove(trackId);
  }

  @override
  Future<bool> hasRecordedAudio(int trackId) async {
    // Fast path: if we armed a recording in this session, trust the cache.
    if (_hasRecording.contains(trackId)) return true;
    // Otherwise ask native (e.g. after hot-reload in dev).
    final state = await _engine.trackState(trackId);
    return state == 3; // kRecorded
  }

  @override
  Future<void> playClick() async {
    // No-op: the native metronome schedules clicks internally. LooperProvider
    // will be rewritten in chunk 9 to drive count-in off the beat stream
    // instead of calling this per beat.
  }
}
