import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin Dart wrapper around the native Stack Looper audio engine.
///
/// Chunk 3: the engine now opens a real duplex Oboe stream (mic + speaker,
/// shared sample clock) when [start] is called. Output is silent and mic
/// samples are discarded — later chunks add click mixing, recording, and
/// track playback.
class NativeAudioEngine {
  static const MethodChannel _channel = MethodChannel('stack_looper/audio');
  static const EventChannel _events = EventChannel('stack_looper/audio_events');

  /// Stream of monotonically-increasing beat indices emitted by the native
  /// engine. A new value is delivered shortly after each click fires
  /// (~<17 ms lag). Safe to listen before [start]; values arrive only after
  /// the engine is running.
  Stream<int> get beatStream => _beatStream ??= _events
      .receiveBroadcastStream()
      .map<int>((dynamic v) => (v as num).toInt());
  Stream<int>? _beatStream;

  Future<String> version() async {
    final result = await _channel.invokeMethod<String>('version');
    return result ?? '<null>';
  }

  /// Opens and starts the duplex audio stream. Idempotent.
  Future<void> start() => _channel.invokeMethod<void>('start');

  /// Stops and closes the duplex audio stream. Idempotent.
  Future<void> stop() => _channel.invokeMethod<void>('stop');

  /// Actual negotiated output sample rate (Oboe may pick a device-preferred
  /// rate instead of our request).
  Future<int> sampleRate() async {
    final rate = await _channel.invokeMethod<int>('sampleRate');
    return rate ?? 0;
  }

  Future<bool> isRunning() async {
    final running = await _channel.invokeMethod<bool>('isRunning');
    return running ?? false;
  }

  /// Sets the metronome tempo. Safe to call while the metronome is running —
  /// takes effect on the next scheduled beat.
  Future<void> setTempoBpm(double bpm) =>
      _channel.invokeMethod<void>('setTempoBpm', bpm);

  /// Starts the metronome. Sample-accurate — the first click fires ~20 ms
  /// after the next audio callback, and subsequent clicks are mathematically
  /// locked to the master sample clock (zero drift).
  Future<void> startMetronome() =>
      _channel.invokeMethod<void>('startMetronome');

  Future<void> stopMetronome() =>
      _channel.invokeMethod<void>('stopMetronome');

    Future<void> setMetronomeAudible(bool audible) async {
      try {
        await _channel.invokeMethod<void>('setMetronomeAudible', audible);
      } on MissingPluginException {
        debugPrint(
          '[NativeAudioEngine] setMetronomeAudible unavailable; full restart required for native update.',
        );
      } on PlatformException catch (error) {
        debugPrint(
          '[NativeAudioEngine] setMetronomeAudible failed: ${error.code} ${error.message}',
        );
      }
    }

  /// Current transport position in sample frames. Master clock.
  Future<int> currentFrame() async {
    final f = await _channel.invokeMethod<int>('currentFrame');
    return f ?? 0;
  }

  /// Samples-per-beat at the current tempo & sample rate. Useful for
  /// computing recording windows in sample frames.
  Future<int> samplesPerBeat() async {
    final s = await _channel.invokeMethod<int>('samplesPerBeat');
    return s ?? 0;
  }

  /// Snapshot of the current beat counter. Prefer listening to [beatStream]
  /// for UI updates; this is for one-shot reads.
  Future<int> currentBeat() async {
    final b = await _channel.invokeMethod<int>('currentBeat');
    return b ?? 0;
  }

  /// Sample frame at which the metronome's next click will fire. Read this
  /// instead of [currentFrame] + [samplesPerBeat] when aligning recording to
  /// an upcoming beat — it's sourced from the audio thread's internal
  /// schedule so it doesn't drift with poll/JNI latency.
  Future<int> nextClickFrame() async {
    final f = await _channel.invokeMethod<int>('nextClickFrame');
    return f ?? 0;
  }

  /// Arms [trackId] to record [lengthFrames] of mic audio, starting when the
  /// transport reaches [startFrame]. If [startFrame] has already passed,
  /// recording begins immediately. Returns false for an invalid trackId.
  Future<bool> armRecording({
    required int trackId,
    required int startFrame,
    required int lengthFrames,
  }) async {
    final ok = await _channel.invokeMethod<bool>('armRecording', {
      'trackId': trackId,
      'startFrame': startFrame,
      'lengthFrames': lengthFrames,
    });
    return ok ?? false;
  }

  /// Raw track state (see TrackState enum in engine.h):
  /// 0=empty, 1=armed, 2=recording, 3=recorded, -1=invalid id.
  Future<int> trackState(int trackId) async {
    final s = await _channel.invokeMethod<int>('trackState', trackId);
    return s ?? -1;
  }

  /// How many mic samples have been captured into this track so far.
  Future<int> trackRecordedSamples(int trackId) async {
    final n =
        await _channel.invokeMethod<int>('trackRecordedSamples', trackId);
    return n ?? 0;
  }

  Future<List<double>> trackWaveformPeaks({
    required int trackId,
    required int bucketCount,
  }) async {
    final raw = await _channel.invokeListMethod<dynamic>('trackWaveformPeaks', {
      'trackId': trackId,
      'bucketCount': bucketCount,
    });
    return raw?.map((value) => (value as num).toDouble()).toList(growable: false) ??
        List<double>.filled(bucketCount, 0.0, growable: false);
  }

  /// Starts seamless looped playback of a recorded track. No-op if empty.
  Future<void> startTrackPlayback(int trackId) =>
      _channel.invokeMethod<void>('startTrackPlayback', trackId);

  Future<void> stopTrackPlayback(int trackId) =>
      _channel.invokeMethod<void>('stopTrackPlayback', trackId);

  Future<bool> isTrackPlaying(int trackId) async {
    final b = await _channel.invokeMethod<bool>('isTrackPlaying', trackId);
    return b ?? false;
  }

  Future<void> clearTrack(int trackId) =>
      _channel.invokeMethod<void>('clearTrack', trackId);

  Future<void> setMasterOutputGainDb(double db) async {
    try {
      await _channel.invokeMethod<void>('setMasterOutputGainDb', db);
    } on MissingPluginException {
      debugPrint(
        '[NativeAudioEngine] setMasterOutputGainDb unavailable; full restart required for native update.',
      );
    } on PlatformException catch (error) {
      debugPrint(
        '[NativeAudioEngine] setMasterOutputGainDb failed: ${error.code} ${error.message}',
      );
    }
  }

  Future<double> masterOutputGainDb() async {
    final value = await _channel.invokeMethod<double>('masterOutputGainDb');
    return value ?? 0.0;
  }

  Future<void> setLimiterCeilingDb(double db) async {
    try {
      await _channel.invokeMethod<void>('setLimiterCeilingDb', db);
    } on MissingPluginException {
      debugPrint(
        '[NativeAudioEngine] setLimiterCeilingDb unavailable; full restart required for native update.',
      );
    } on PlatformException catch (error) {
      debugPrint(
        '[NativeAudioEngine] setLimiterCeilingDb failed: ${error.code} ${error.message}',
      );
    }
  }

  Future<double> limiterCeilingDb() async {
    final value = await _channel.invokeMethod<double>('limiterCeilingDb');
    return value ?? -1.0;
  }

  Future<void> setHighPassHz(double hz) async {
    try {
      await _channel.invokeMethod<void>('setHighPassHz', hz);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setHighPassHz unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setHighPassHz failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setLowPassHz(double hz) async {
    try {
      await _channel.invokeMethod<void>('setLowPassHz', hz);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setLowPassHz unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setLowPassHz failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setEqLowDb(double db) async {
    try {
      await _channel.invokeMethod<void>('setEqLowDb', db);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setEqLowDb unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setEqLowDb failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setEqMidDb(double db) async {
    try {
      await _channel.invokeMethod<void>('setEqMidDb', db);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setEqMidDb unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setEqMidDb failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setEqHighDb(double db) async {
    try {
      await _channel.invokeMethod<void>('setEqHighDb', db);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setEqHighDb unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setEqHighDb failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setCompressorAmount(double amount) async {
    try {
      await _channel.invokeMethod<void>('setCompressorAmount', amount);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setCompressorAmount unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setCompressorAmount failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setDistortionAmount(double amount) async {
    try {
      await _channel.invokeMethod<void>('setDistortionAmount', amount);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setDistortionAmount unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setDistortionAmount failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setSaturationAmount(double amount) async {
    try {
      await _channel.invokeMethod<void>('setSaturationAmount', amount);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setSaturationAmount unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setSaturationAmount failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setDelaySend(double amount) async {
    try {
      await _channel.invokeMethod<void>('setDelaySend', amount);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setDelaySend unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setDelaySend failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setDelayDivision(int division) async {
    try {
      await _channel.invokeMethod<void>('setDelayDivision', division);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setDelayDivision unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setDelayDivision failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setDelayFeel(int feel) async {
    try {
      await _channel.invokeMethod<void>('setDelayFeel', feel);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setDelayFeel unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setDelayFeel failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setReverbSend(double amount) async {
    try {
      await _channel.invokeMethod<void>('setReverbSend', amount);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setReverbSend unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setReverbSend failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setReverbRoomSize(double amount) async {
    try {
      await _channel.invokeMethod<void>('setReverbRoomSize', amount);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setReverbRoomSize unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setReverbRoomSize failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setDjFilterAmount(double amount) async {
    try {
      await _channel.invokeMethod<void>('setDjFilterAmount', amount);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setDjFilterAmount unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setDjFilterAmount failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setDjFilterResonance(double amount) async {
    try {
      await _channel.invokeMethod<void>('setDjFilterResonance', amount);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setDjFilterResonance unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setDjFilterResonance failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setBeatRepeatMix(double amount) async {
    try {
      await _channel.invokeMethod<void>('setBeatRepeatMix', amount);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setBeatRepeatMix unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setBeatRepeatMix failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setBeatRepeatDivision(int division) async {
    try {
      await _channel.invokeMethod<void>('setBeatRepeatDivision', division);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setBeatRepeatDivision unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setBeatRepeatDivision failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setTransGateAmount(double amount) async {
    try {
      await _channel.invokeMethod<void>('setTransGateAmount', amount);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setTransGateAmount unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setTransGateAmount failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setTransGateDivision(int division) async {
    try {
      await _channel.invokeMethod<void>('setTransGateDivision', division);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setTransGateDivision unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setTransGateDivision failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setNoiseRiserAmount(double amount) async {
    try {
      await _channel.invokeMethod<void>('setNoiseRiserAmount', amount);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setNoiseRiserAmount unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setNoiseRiserAmount failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setTapeStopAmount(double amount) async {
    try {
      await _channel.invokeMethod<void>('setTapeStopAmount', amount);
    } on MissingPluginException {
      debugPrint('[NativeAudioEngine] setTapeStopAmount unavailable; full restart required.');
    } on PlatformException catch (error) {
      debugPrint('[NativeAudioEngine] setTapeStopAmount failed: ${error.code} ${error.message}');
    }
  }

  Future<void> setTrackOutputGainDb({
    required int trackId,
    required double db,
  }) async {
    try {
      await _channel.invokeMethod<void>('setTrackOutputGainDb', {
        'trackId': trackId,
        'db': db,
      });
    } on MissingPluginException {
      debugPrint(
        '[NativeAudioEngine] setTrackOutputGainDb unavailable; full restart required for native update.',
      );
    } on PlatformException catch (error) {
      debugPrint(
        '[NativeAudioEngine] setTrackOutputGainDb failed: ${error.code} ${error.message}',
      );
    }
  }

  Future<double> trackOutputGainDb(int trackId) async {
    final value = await _channel.invokeMethod<double>('trackOutputGainDb', trackId);
    return value ?? 0.0;
  }

  Future<void> setTrackDelaySendEnabled({
    required int trackId,
    required bool enabled,
  }) async {
    try {
      await _channel.invokeMethod<void>('setTrackDelaySendEnabled', {
        'trackId': trackId,
        'enabled': enabled,
      });
    } on MissingPluginException {
      debugPrint(
        '[NativeAudioEngine] setTrackDelaySendEnabled unavailable; full restart required.',
      );
    } on PlatformException catch (error) {
      debugPrint(
        '[NativeAudioEngine] setTrackDelaySendEnabled failed: ${error.code} ${error.message}',
      );
    }
  }

  Future<void> setTrackReverbSendEnabled({
    required int trackId,
    required bool enabled,
  }) async {
    try {
      await _channel.invokeMethod<void>('setTrackReverbSendEnabled', {
        'trackId': trackId,
        'enabled': enabled,
      });
    } on MissingPluginException {
      debugPrint(
        '[NativeAudioEngine] setTrackReverbSendEnabled unavailable; full restart required.',
      );
    } on PlatformException catch (error) {
      debugPrint(
        '[NativeAudioEngine] setTrackReverbSendEnabled failed: ${error.code} ${error.message}',
      );
    }
  }
}
