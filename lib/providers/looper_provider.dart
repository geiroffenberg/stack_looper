import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../models/looper_state.dart';
import '../models/track.dart';
import '../services/audio_service.dart';
import '../services/native_audio_service.dart';

class LooperProvider extends ChangeNotifier {
  static const int _waveformBucketsPerBar = 32;
  static const int _beatsPerBar = 4;

  LooperProvider({AudioService? audioService})
      : _audioService = audioService ?? AudioServiceStub(),
        _state = LooperState(
          tracks: List.generate(
            AppConstants.maxTracks,
            (index) => Track(
              id: index,
              barLength: AppConstants.defaultBarLength,
            ),
          ),
          selectedTrackIndex: 0,
          bpm: AppConstants.defaultBpm,
          repeatCount: AppConstants.defaultRepeatCount,
          numTracksToRecord: 1,
          transportState: TransportState.stopped,
        );

  final AudioService _audioService;

  // The native service exposes extra APIs (beat stream, sample-accurate
  // arming, tempo control) beyond the AudioService interface. Stored as a
  // typed handle when present so we can drive count-in and recording from
  // the native transport clock instead of Dart timers.
  NativeAudioService? get _native =>
      _audioService is NativeAudioService ? _audioService : null;

  LooperState _state;
  final Set<int> _activeRecordingTrackIds = <int>{};
  Timer? _recordingTimer;
  Timer? _armStartTimer;
  Timer? _armedBlinkTimer;
  bool _beatFlash = false;
  bool _recordArmed = false;
  bool _armedBlinkOn = false;
  int? _armedTrackId;
  bool _suppressMetronomeClicks = false;
  int? _playbackAnchorFrame;

  // Native beat plumbing. _beatSub listens for the whole lifetime of the
  // transport (count-in → recording). _countInBaseBeat anchors local beat 1
  // to whatever the first native beat event is, so this code doesn't care
  // about the monotonic native beat index.
  StreamSubscription<int>? _beatSub;
  int _localBeat = 0;      // 1-based beat counter within the current session
  int? _countInBaseBeat;   // native beat index that corresponds to local=1
  List<int> _pendingTargets = const [];

  // Chain-record state. When numTracksToRecord > 1, we fill empty tracks
  // back-to-back without requiring another tap: count-in once, then each
  // track is armed with its own start_frame/length on the native side and
  // the engine hands off seamlessly between them. Dart tracks which target
  // is "currently recording" for UI purposes.
  List<int> _chainTargets = const [];     // ordered track IDs to fill
  List<int> _chainStartBeats = const [];  // local beat each target begins at
  int _chainCurrentIdx = 0;               // index into _chainTargets

  LooperState get state => _state;

  bool get beatFlash => _beatFlash;
  bool get recordArmed => _recordArmed;
  bool get armedBlinkOn => _armedBlinkOn;
  int? get armedTrackId => _armedTrackId;

  int get visualBarDividers =>
      _state.tracks.any((track) => track.barLength == 8) ? 8 : 4;

  List<int> get availableNumTracksToRecordOptions {
    if (_state.hasRecordedTracks) {
      return const [1];
    }
    final int empty = _state.emptyTrackCount;
    if (empty <= 0) {
      return const [1];
    }
    return List<int>.generate(empty, (i) => i + 1);
  }

  bool get canStartRecording =>
      _state.transportState == TransportState.recording ||
      _state.transportState == TransportState.countIn ||
      _state.emptyTrackCount > 0;

  void setBpm(int bpm) {
    final clamped = bpm.clamp(AppConstants.minBpm, AppConstants.maxBpm);
    _state = _state.copyWith(bpm: clamped);
    // Keep the native engine's tempo in sync so count-in clicks and
    // sample-per-beat math use the latest value.
    _native?.setTempoBpm(clamped.toDouble());
    notifyListeners();
  }

  void setRepeatCount(int repeatCount) {
    _state = _state.copyWith(repeatCount: repeatCount);
    notifyListeners();
  }

  void setNumTracksToRecord(int count) {
    if (_state.hasRecordedTracks) {
      if (_state.numTracksToRecord != 1) {
        _state = _state.copyWith(numTracksToRecord: 1);
        notifyListeners();
      }
      return;
    }
    final int maxSelectable = _maxSelectableTrackCount();
    _state = _state.copyWith(numTracksToRecord: count.clamp(1, maxSelectable));
    notifyListeners();
  }

  void selectTrack(int index) {
    // Manual track selection is intentionally disabled.
  }

  void setTrackBarLength(int trackId, int barLength) {
    _updateTrack(trackId, (track) => track.copyWith(barLength: barLength));
  }

  void toggleMute(int trackId) {
    final Track track = _state.tracks[trackId];
    if (!track.hasAudio) {
      return;
    }
    _updateTrack(trackId, (t) => t.copyWith(isMuted: !t.isMuted));
  }

  Future<void> playAll() async {
    if (_state.transportState == TransportState.countIn) {
      await _cancelCountIn();
      return;
    }

    if (_state.transportState == TransportState.stopped) {
      if (!_state.hasRecordedTracks) {
        return;
      }
      await _startPlayback();
      return;
    }

    if (_state.transportState == TransportState.recording) {
      await _stopRecording(continuePlayback: false);
    }

    await stopAll();
  }

  Future<void> stopAll() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _armStartTimer?.cancel();
    _armStartTimer = null;
    _stopArmedBlink();
    _recordArmed = false;
    _armedTrackId = null;
    await _stopBeatListener();
    _beatFlash = false;
    _localBeat = 0;
    _countInBaseBeat = null;
    _playbackAnchorFrame = null;
    _resetChainState();
    await _audioService.stopAll();

    _activeRecordingTrackIds.clear();
    final List<Track> updated = _state.tracks
        .map(
          (track) => !track.hasAudio
              ? track.copyWith(state: TrackState.empty, isMuted: false)
              : track.copyWith(
                  state: TrackState.playing,
                  isMuted: track.isMuted,
                ),
        )
        .toList(growable: false);

    _state = _state.copyWith(
      tracks: updated,
      transportState: TransportState.stopped,
      selectedTrackIndex: _firstEmptyTrackIndex(),
      numTracksToRecord: _state.hasRecordedTracks ? 1 : _state.numTracksToRecord,
    );
    notifyListeners();
  }

  Future<void> startRecordingSession() async {
    if (_state.transportState == TransportState.countIn) {
      await _cancelCountIn();
      return;
    }

    if (_state.transportState == TransportState.recording) {
      await _stopRecording(continuePlayback: true);
      return;
    }

    if (_state.emptyTrackCount <= 0) {
      _state = _state.copyWith(selectedTrackIndex: -1);
      notifyListeners();
      return;
    }

    // If already playing, arm a single-track recording for the next master
    // loop boundary (no audible count-in).
    if (_state.transportState == TransportState.playing) {
      final int targetStart = _resolveTargetStart();
      if (targetStart < 0) return;
      await _armSingleTrackOnNextMasterBoundary(targetStart);
      return;
    }

    final int targetStart = _resolveTargetStart();
    if (targetStart >= 0 && targetStart != _state.selectedTrackIndex) {
      _state = _state.copyWith(selectedTrackIndex: targetStart);
      notifyListeners();
    }

    // Multi-track chain only applies at the very beginning (all tracks empty,
    // starting from track 1). Any later additions are single-track recordings.
    final bool canChain = !_state.hasRecordedTracks && targetStart == 0;
    final int desiredTracks = canChain ? _state.numTracksToRecord : 1;

    final targets = _targetTrackIndexes(
      startIndex: targetStart,
      desiredCount: desiredTracks,
    );
    if (targets.isEmpty) {
      return;
    }

    _activeRecordingTrackIds
      ..clear()
      ..addAll(targets);

    await _startCountIn(targets);
  }

  int _resolveTargetStart() {
    final int selected = _state.selectedTrackIndex;
    return (selected >= 0 &&
            selected < _state.tracks.length &&
            !_state.tracks[selected].hasAudio)
        ? selected
        : _firstEmptyTrackIndex();
  }

  Future<void> _armSingleTrackOnNextMasterBoundary(int trackId) async {
    final native = _native;
    if (native == null) return;

    _activeRecordingTrackIds
      ..clear()
      ..add(trackId);

    // Show armed UI immediately when the user presses record while playing.
    _recordArmed = true;
    _armedTrackId = trackId;
    _suppressMetronomeClicks = true;
    _startArmedBlink();

    final List<Track> armedTracks = _state.tracks
        .map(
          (track) => track.id == trackId
              ? track.copyWith(state: TrackState.armed)
              : track.hasAudio
                  ? track.copyWith(state: TrackState.looping)
                  : track.copyWith(state: TrackState.empty),
        )
        .toList(growable: false);
    _state = _state.copyWith(
      tracks: armedTracks,
      selectedTrackIndex: trackId,
      transportState: TransportState.playing,
      numTracksToRecord: 1,
    );
    notifyListeners();

    final int spb = await native.engine.samplesPerBeat();
    final int sampleRate = await native.engine.sampleRate();
    final int now = await native.engine.currentFrame();

    final int targetBars = _state.tracks[trackId].barLength;
    final int cycleBars = _longestPopulatedBarLength();
    final int masterCycleFrames = cycleBars * _beatsPerBar * spb;
    final int anchor = _playbackAnchorFrame ?? now;
    int startFrame = anchor + (((now - anchor) ~/ masterCycleFrames) + 1) * masterCycleFrames;
    if (startFrame <= now) {
      startFrame += masterCycleFrames;
    }

    final int lengthFrames = targetBars * _beatsPerBar * spb;

    await native.engine.armRecording(
      trackId: trackId,
      startFrame: startFrame,
      lengthFrames: lengthFrames,
    );

    await native.setTempoBpm(_state.bpm.toDouble());
    await native.setMetronomeAudible(false);
    _beatSub = native.beatStream.listen(_onNativeBeat);
    await native.startMetronome();
    await native.setMetronomeAudible(false);

    final int msUntilStart =
        (((startFrame - now) * 1000) / sampleRate).round().clamp(0, 1 << 30);

    _armStartTimer?.cancel();
    _armStartTimer = Timer(Duration(milliseconds: msUntilStart), () {
      if (!_recordArmed || _armedTrackId != trackId) return;
      _recordArmed = false;
      _armedTrackId = null;
      _stopArmedBlink();

      final List<Track> tracks = _state.tracks
          .map(
            (track) => track.id == trackId
                ? track.copyWith(state: TrackState.recording)
                : track,
          )
          .toList(growable: false);
      _state = _state.copyWith(
        tracks: tracks,
        transportState: TransportState.recording,
      );
      notifyListeners();
    });

    _recordingTimer?.cancel();
    _recordingTimer = Timer(
      Duration(milliseconds: msUntilStart + ((lengthFrames * 1000) / sampleRate).round()),
      () => _stopRecording(continuePlayback: true),
    );

    // Anchor for future loop-phase alignment: the native engine begins the
    // new track's playback loop precisely at startFrame + lengthFrames.
    _playbackAnchorFrame = startFrame + lengthFrames;
  }

  int _longestPopulatedBarLength() {
    int longest = 1;
    for (final t in _state.tracks) {
      final bool isPopulated =
          t.hasAudio ||
          t.state == TrackState.playing ||
          t.state == TrackState.looping;
      if (isPopulated && t.barLength > longest) {
        longest = t.barLength;
      }
    }
    return longest;
  }

  void _startArmedBlink() {
    _armedBlinkTimer?.cancel();
    _armedBlinkOn = true;
    _armedBlinkTimer = Timer.periodic(const Duration(milliseconds: 260), (_) {
      _armedBlinkOn = !_armedBlinkOn;
      notifyListeners();
    });
  }

  void _stopArmedBlink() {
    _armedBlinkTimer?.cancel();
    _armedBlinkTimer = null;
    _armedBlinkOn = false;
  }

  Future<void> _cancelCountIn() async {
    await _stopBeatListener();
    _beatFlash = false;
    _localBeat = 0;
    _countInBaseBeat = null;
    _pendingTargets = const [];
    _playbackAnchorFrame = null;
    _resetChainState();
    _recordArmed = false;
    _armedTrackId = null;
    _suppressMetronomeClicks = false;
    _armStartTimer?.cancel();
    _armStartTimer = null;
    _stopArmedBlink();
    _activeRecordingTrackIds.clear();
    _state = _state.copyWith(transportState: TransportState.stopped);
    notifyListeners();
  }

  void _resetChainState() {
    _chainTargets = const [];
    _chainStartBeats = const [];
    _chainCurrentIdx = 0;
  }

  /// Count-in: 4 audible clicks from the native metronome, then recording
  /// arms sample-accurately on the next downbeat. Native engine drives the
  /// clock — Dart just listens to beat events and decides when to transition.
  Future<void> _startCountIn(List<int> targets) async {
    final native = _native;
    if (native == null) {
      // Keep state semantics for tests/non-native environments: enter
      // count-in, but do not try to drive native timing.
      _pendingTargets = List<int>.from(targets);
      _state = _state.copyWith(transportState: TransportState.countIn);
      notifyListeners();
      debugPrint('[LooperProvider] no NativeAudioService; count-in visual only');
      return;
    }

    _pendingTargets = List<int>.from(targets);
    _localBeat = 0;
    _countInBaseBeat = null;
    _playbackAnchorFrame = null;
    _suppressMetronomeClicks = false;

    await _audioService.stopAll();
    _state = _state.copyWith(transportState: TransportState.countIn);
    notifyListeners();
    _flashBeat();

    // Make sure native tempo matches current bpm before starting the click.
    await native.setTempoBpm(_state.bpm.toDouble());
    await native.setMetronomeAudible(true);

    // Subscribe BEFORE starting the metronome so we don't miss beat 1.
    _beatSub = native.beatStream.listen(_onNativeBeat);
    await native.startMetronome();
  }

  Future<void> _stopBeatListener() async {
    await _beatSub?.cancel();
    _beatSub = null;
    await _native?.stopMetronome();
  }

  void _onNativeBeat(int nativeBeat) {
    if (_suppressMetronomeClicks) {
      unawaited(_native?.setMetronomeAudible(false) ?? Future<void>.value());
    }

    // Anchor on the FIRST event so local beat 1 lines up with the first
    // audible click of this count-in, regardless of the engine's monotonic
    // beat counter.
    _countInBaseBeat ??= nativeBeat - 1;
    _localBeat = nativeBeat - _countInBaseBeat!;

    if (_state.transportState == TransportState.countIn) {
      _flashBeat();
      if (_localBeat == 4) {
        // Fourth click just fired. Arm recording on the next downbeat —
        // audio thread will transition to recording/playback on the exact
        // sample. Mute the metronome NOW so the upcoming recording downbeat
        // is silent; if we wait until beat 5, that click has already played.
        // We DON'T flip the UI state here; that would start the playhead a
        // full beat before the audio downbeat.
        unawaited(_native?.setMetronomeAudible(false) ?? Future<void>.value());
        unawaited(_armRecordingOnNextDownbeat());
      } else if (_localBeat >= 5) {
        // Beat-5 event = the recording downbeat just fired. Flip the UI
        // here so the playhead starts in lockstep with the audible click.
        _flipToRecordingState();
      }
    } else if (_state.transportState == TransportState.recording) {
      // Keep the UI beat flash ticking during recording so the musician has
      // a visual reference that matches the audible click.
      _flashBeat();
      _advanceChainIfNeeded();
      for (final trackId in _activeRecordingTrackIds) {
        unawaited(_refreshTrackWaveform(trackId));
      }
    }
  }

  /// If this beat has moved us into the next target's recording window,
  /// flip the previous target to "looping" and the new target to
  /// "recording". Called on every beat during a chain-record session.
  void _advanceChainIfNeeded() {
    if (_chainTargets.length <= 1) return;
    final int nextIdx = _chainCurrentIdx + 1;
    if (nextIdx >= _chainTargets.length) return;
    if (_localBeat < _chainStartBeats[nextIdx]) return;

    final int prevId = _chainTargets[_chainCurrentIdx];
    final int newId = _chainTargets[nextIdx];
    _chainCurrentIdx = nextIdx;

    final List<Track> updated = _state.tracks.map((track) {
      if (track.id == prevId) {
        // Native engine has already auto-started playback on this track.
        return track.copyWith(
          hasAudio: true,
          state: TrackState.looping,
        );
      }
      if (track.id == newId) {
        return track.copyWith(state: TrackState.recording);
      }
      return track;
    }).toList(growable: false);

    _state = _state.copyWith(
      tracks: updated,
      selectedTrackIndex: newId,
    );
    notifyListeners();
  }

  void _flipToRecordingState() {
    if (_chainTargets.isEmpty) return;

    final int currentId = _chainTargets[_chainCurrentIdx];
    final List<Track> updatedTracks = _state.tracks
        .map(
          (track) => track.id == currentId
              ? track.copyWith(state: TrackState.recording)
              : track.hasAudio
                  ? track.copyWith(state: TrackState.looping)
                  : track.copyWith(state: TrackState.empty),
        )
        .toList(growable: false);

    _state = _state.copyWith(
      tracks: updatedTracks,
      selectedTrackIndex: currentId,
      transportState: TransportState.recording,
    );
    notifyListeners();
    _flashBeat();

    unawaited(_playAudibleTracks(_state.tracks, resetAnchor: true));
  }

  void _flashBeat() {
    _beatFlash = true;
    notifyListeners();
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (_beatFlash) {
        _beatFlash = false;
        notifyListeners();
      }
    });
  }

  /// Arms recording for every pending target sequentially. Called once,
  /// immediately after beat 4 of the count-in fires.
  ///
  /// Each target gets its own start_frame. Between targets, we insert a
  /// delay controlled by `repeatCount` and the just-recorded track length:
  ///   delay = repeatCount * (trackBarLength * beatsPerBar)
  ///
  /// Example: if a track records 2 bars and repeatCount=1, that 2-bar loop
  /// plays exactly one more time before the next track begins recording.
  ///
  /// The native engine auto-transitions the
  /// previous track to kRecorded → playback on the same sample the next
  /// track's armed → recording transition fires, giving a seamless,
  /// click-free hand-off between takes with zero Dart involvement.
  Future<void> _armRecordingOnNextDownbeat() async {
    final native = _native;
    if (native == null) return;
    if (_pendingTargets.isEmpty) return;

    final targets = _pendingTargets;
    _pendingTargets = const [];

    final spb = await native.engine.samplesPerBeat();
    // Use the engine's own scheduled next-click frame rather than
    // currentFrame + spb. The audio thread knows exactly when the next
    // click will fire (sample-accurate); currentFrame + spb drifts by
    // poll interval + JNI latency (~15–30 ms) and would make recording
    // start just after the audible downbeat click.
    final int firstStartFrame = await native.engine.nextClickFrame();
    const int beatsPerBar = _beatsPerBar;
    final int repeatCount = _state.repeatCount;

    // Walk the targets list, arming each with a start_frame that follows
    // immediately after the previous one. Also record the local-beat
    // position of each target's start/end so _advanceChainIfNeeded() can
    // flip UI states at the right moment.
    final List<int> starts = <int>[];
    int currentStart = firstStartFrame;
    int localBeatCursor = 5;  // beat 5 = first recording downbeat
    int totalLengthFrames = 0;
    for (int i = 0; i < targets.length; i++) {
      final trackIndex = targets[i];
      final int barLen = _state.tracks[trackIndex].barLength;
      final int lengthFrames = spb * barLen * beatsPerBar;
      await native.engine.armRecording(
        trackId: trackIndex,
        startFrame: currentStart,
        lengthFrames: lengthFrames,
      );
      starts.add(localBeatCursor);
      localBeatCursor += barLen * beatsPerBar;
      currentStart += lengthFrames;
      totalLengthFrames += lengthFrames;

      // Repeat delay between tracks is based on the length of the track that
      // just finished recording.
      if (i < targets.length - 1 && repeatCount > 0) {
        final int repeatDelayBeats = repeatCount * barLen * beatsPerBar;
        final int repeatDelayFrames = repeatDelayBeats * spb;
        currentStart += repeatDelayFrames;
        totalLengthFrames += repeatDelayFrames;
        localBeatCursor += repeatDelayBeats;
      }
    }

    _chainTargets = List<int>.from(targets);
    _chainStartBeats = starts;
    _chainCurrentIdx = 0;

    // Anchor loop phase to the first target's loop origin (= its record end).
    final int firstTargetBars = _state.tracks[targets.first].barLength;
    _playbackAnchorFrame =
        firstStartFrame + (firstTargetBars * beatsPerBar * spb);

    // UI state flip is deferred to the beat-5 event (see _onNativeBeat) so
    // the playhead animation kicks off exactly when the audio downbeat
    // fires. Recording-end is scheduled from "now" + wait-for-downbeat +
    // total-record-length.
    final int sampleRate = await native.engine.sampleRate();
    final int nowFrame = await native.engine.currentFrame();
    final int framesUntilStart = firstStartFrame - nowFrame;
    final int msUntilStart = framesUntilStart > 0
        ? ((framesUntilStart * 1000) / sampleRate).round()
        : 0;
    final int durationMs =
        msUntilStart + (totalLengthFrames * 1000 / sampleRate).round();
    _recordingTimer?.cancel();
    _recordingTimer = Timer(Duration(milliseconds: durationMs), () {
      _stopRecording(continuePlayback: true);
    });
  }

  Future<void> deleteTrackAudio(int trackId) async {
    await _audioService.deleteTrack(trackId);
    _activeRecordingTrackIds.remove(trackId);

    _updateTrack(
      trackId,
      (track) => track.copyWith(
        hasAudio: false,
        isMuted: false,
        state: TrackState.empty,
        waveformPeaks: const <double>[],
      ),
    );

    final int maxSelectable = _maxSelectableTrackCount();
    if (_state.numTracksToRecord > maxSelectable) {
      _state = _state.copyWith(numTracksToRecord: maxSelectable);
      notifyListeners();
    }

    _state = _state.copyWith(
      selectedTrackIndex: _firstEmptyTrackIndex(),
      numTracksToRecord: _state.hasRecordedTracks ? 1 : _state.numTracksToRecord,
    );
    notifyListeners();
  }

  List<int> _targetTrackIndexes({
    required int startIndex,
    required int desiredCount,
  }) {
    final int selected = startIndex < 0 ? 0 : startIndex;
    final List<int> ordered = [
      ...List<int>.generate(_state.tracks.length - selected, (i) => i + selected),
      ...List<int>.generate(selected, (i) => i),
    ];

    final emptyTracks = ordered.where((i) => !_state.tracks[i].hasAudio).toList();
    final int count = desiredCount.clamp(1, emptyTracks.length);
    return emptyTracks.take(count).toList();
  }

  Future<void> _startPlayback() async {
    final List<Track> updated = _state.tracks
        .map(
          (track) => !track.hasAudio
              ? track.copyWith(state: TrackState.empty)
              : track.copyWith(state: TrackState.looping),
        )
        .toList(growable: false);

    _state = _state.copyWith(
      tracks: updated,
      transportState: TransportState.playing,
      selectedTrackIndex: _firstEmptyTrackIndex(),
    );
    notifyListeners();

    await _playAudibleTracks(updated, resetAnchor: true);
  }

  Future<void> _stopRecording({required bool continuePlayback}) async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _armStartTimer?.cancel();
    _armStartTimer = null;
    _recordArmed = false;
    _armedTrackId = null;
    _suppressMetronomeClicks = false;
    _stopArmedBlink();
    await _stopBeatListener();
    _beatFlash = false;
    _localBeat = 0;
    _countInBaseBeat = null;
    _resetChainState();

    if (_activeRecordingTrackIds.isEmpty) {
      _state = _state.copyWith(
        transportState: continuePlayback ? TransportState.playing : TransportState.stopped,
        selectedTrackIndex: _firstEmptyTrackIndex(),
        numTracksToRecord: _state.hasRecordedTracks ? 1 : _state.numTracksToRecord,
      );
      notifyListeners();
      return;
    }

    final Set<int> finalizedTrackIds = Set<int>.from(_activeRecordingTrackIds);
    for (final trackId in finalizedTrackIds) {
      await _audioService.stopTrackRecording(trackId);
      await _refreshTrackWaveform(trackId);
    }

    final List<Track> updatedTracks = _state.tracks
        .map(
          (track) => finalizedTrackIds.contains(track.id)
              ? track.copyWith(
                  hasAudio: true,
                  state: continuePlayback ? TrackState.looping : TrackState.playing,
                )
              : track.hasAudio
                  ? track.copyWith(
                      state: continuePlayback ? TrackState.looping : TrackState.playing,
                    )
                  : track.copyWith(state: TrackState.empty),
        )
        .toList(growable: false);

    _activeRecordingTrackIds.clear();

    _state = _state.copyWith(
      tracks: updatedTracks,
      transportState: continuePlayback ? TransportState.playing : TransportState.stopped,
      selectedTrackIndex: _nextEmptyTrackIndexAfter(
        _selectionAnchorTrackId(finalizedTrackIds),
      ),
      numTracksToRecord: 1,
    );
    notifyListeners();

    if (continuePlayback) {
      await _playAudibleTracks(updatedTracks, resetAnchor: true);
    } else {
      _playbackAnchorFrame = null;
    }
  }

  Future<void> _playAudibleTracks(List<Track> tracks, {bool resetAnchor = false}) async {
    // Loop-phase anchor is set precisely when recording is armed, based on
    // the engine's sample-accurate start/length. Capturing currentFrame here
    // would introduce Dart-call latency and drift the phase, so we ignore
    // resetAnchor unless no anchor has been set yet.
    if (resetAnchor && _playbackAnchorFrame == null) {
      final native = _native;
      if (native != null) {
        _playbackAnchorFrame = await native.engine.currentFrame();
      }
    }
    for (final track in tracks.where((t) => t.hasAudio && !t.isMuted)) {
      await _audioService.playTrack(track.id, loop: true);
    }
  }

  Future<void> _refreshTrackWaveform(int trackId) async {
    final native = _native;
    if (native == null) return;
    final int barLength = _state.tracks[trackId].barLength;
    final int bucketCount = barLength * _waveformBucketsPerBar;
    final peaks = await native.trackWaveformPeaks(
      trackId: trackId,
      bucketCount: bucketCount,
    );
    _updateTrack(
      trackId,
      (track) => track.copyWith(waveformPeaks: peaks),
    );
  }

  void _updateTrack(int trackId, Track Function(Track) update) {
    final List<Track> updatedTracks = List<Track>.from(_state.tracks);
    updatedTracks[trackId] = update(updatedTracks[trackId]);
    _state = _state.copyWith(tracks: updatedTracks);
    notifyListeners();
  }

  int _maxSelectableTrackCount() {
    return _state.emptyTrackCount.clamp(1, AppConstants.maxTracks);
  }

  int _firstEmptyTrackIndex() {
    final int idx = _state.tracks.indexWhere((t) => !t.hasAudio);
    return idx >= 0 ? idx : -1;
  }

  int _selectionAnchorTrackId(Set<int> finalizedTrackIds) {
    if (_chainTargets.isNotEmpty) {
      return _chainTargets.last;
    }
    if (finalizedTrackIds.isEmpty) {
      return _state.selectedTrackIndex;
    }
    return finalizedTrackIds.reduce((a, b) => a > b ? a : b);
  }

  int _nextEmptyTrackIndexAfter(int anchorTrackId) {
    if (_state.emptyTrackCount <= 0) {
      return -1;
    }

    final int trackCount = _state.tracks.length;
    final int normalizedAnchor =
        anchorTrackId < 0 ? 0 : (anchorTrackId % trackCount);

    for (int step = 1; step <= trackCount; step++) {
      final int idx = (normalizedAnchor + step) % trackCount;
      if (!_state.tracks[idx].hasAudio) {
        return idx;
      }
    }

    return -1;
  }
}
