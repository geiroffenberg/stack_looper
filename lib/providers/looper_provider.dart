import 'dart:async';

import 'package:flutter/foundation.dart';
import 'dart:math' as math;

import '../constants/app_constants.dart';
import '../models/looper_state.dart';
import '../models/track.dart';
import '../services/audio_service.dart';
import '../services/native_audio_service.dart';

class LooperProvider extends ChangeNotifier {
  static const int _waveformBucketsPerBar = 32;
  static const int _beatsPerBar = 4;
  static const double _defaultTrackDelaySendLevel = 1.0;
  static const double _defaultTrackReverbSendLevel = 1.0;
  static const double _trackMinOutputDb = -60.0;
  static const double _trackMaxOutputDb = 12.0;
  static const double _muteThreshold = 0.001;

  LooperProvider({AudioService? audioService})
    : _audioService = audioService ?? AudioServiceStub(),
      _state = LooperState(
        tracks: List.generate(
          AppConstants.maxTracks,
          (index) => Track(id: index, barLength: AppConstants.defaultBarLength),
        ),
        selectedTrackIndex: 0,
        bpm: AppConstants.defaultBpm,
        repeatCount: AppConstants.defaultRepeatCount,
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
  final List<Timer> _recordingSequenceUiTimers = <Timer>[];
  Timer? _armedBlinkTimer;
  bool _beatFlash = false;
  bool _recordArmed = false;
  bool _armedBlinkOn = false;
  int? _armedTrackId;
  bool _suppressMetronomeClicks = false;
  int? _playbackAnchorFrame;
  bool _headphoneSafetyEnabled = false;
  List<int> _selectedLoopTrackIds = const [0];

  // Song tracks: three fixed capture slots (A / B / C), native IDs 0,1,2.
  List<SongTrack> _songTracks = List<SongTrack>.unmodifiable([
    SongTrack(id: 100, label: 'A'),
    SongTrack(id: 101, label: 'B'),
    SongTrack(id: 102, label: 'C'),
  ]);
  int? _activeSongTrackId;
  int? _selectedSongTrackId; // song track currently in exclusive solo mode
  // Pending quantized song track change (committed at next master loop downbeat).
  // _pendingSongTrackChange == true means a change is staged.
  // _pendingSongTrackId == null means "restore to loop tracks"; a specific id
  // means "switch solo to that track".
  bool _pendingSongTrackChange = false;
  int? _pendingSongTrackId;
  Timer? _songTrackDownbeatTimer; // fires at each master loop restart during playback
  List<bool>? _savedLoopMuteStates; // loop track mutes saved before entering solo
  int _songTrackScheduleToken = 0;
  bool _pendingSongTrackScheduledNatively = false;

  // Master FX page state.
  bool _fxEnabled = true;
  double _fxHighPassHz = 20.0;
  double _fxLowPassHz = 20000.0;
  double _fxEqLowDb = 0.0;
  double _fxEqMidDb = 0.0;
  double _fxEqHighDb = 0.0;
  double _fxCompressorAmount = 0.0;
  double _fxSaturationAmount = 0.0;
  int _fxDelayDivision = 8;
  int _fxDelayFeel = 0;
  double _fxDelayFeedback = 0.4;
  double _fxDelayInput = 0.85;
  double _fxReverbRoomSize = 0.5;
  double _fxReverbDamping = 0.55;
  double _fxLimiterCeilingDb = -1.0;
  double _fxMasterOutputDb = 0.0;
  late final List<double> _fxTrackOutputDb = List<double>.filled(
    AppConstants.maxTracks,
    0.0,
    growable: false,
  );
  late final List<double?> _preMuteTrackOutputDb = List<double?>.filled(
    AppConstants.maxTracks,
    null,
    growable: false,
  );

  // Native beat plumbing. _beatSub listens for the whole lifetime of the
  // transport (count-in → recording). _countInBaseBeat anchors local beat 1
  // to whatever the first native beat event is, so this code doesn't care
  // about the monotonic native beat index.
  StreamSubscription<int>? _beatSub;
  int _localBeat = 0; // 1-based beat counter within the current session
  int? _countInBaseBeat; // native beat index that corresponds to local=1
  List<int> _pendingTargets = const [];

  // Sequential selected-track recording state. Once recording starts, the
  // chosen targets are armed back-to-back on the native side and the engine
  // hands off seamlessly between them. Dart tracks which target is currently
  // recording for UI purposes.
  List<int> _recordingSequenceTargets = const []; // ordered track IDs to fill
  List<int> _recordingSequenceStartBeats = const []; // local beat each target begins at
  int _recordingSequenceCurrentIdx = 0; // index into _recordingSequenceTargets

  LooperState get state => _state;

  bool get beatFlash => _beatFlash;
  bool get recordArmed => _recordArmed;
  bool get armedBlinkOn => _armedBlinkOn;
  int? get armedTrackId => _armedTrackId;
  bool get headphoneSafetyEnabled => _headphoneSafetyEnabled;
  List<int> get selectedLoopTrackIds =>
      List<int>.unmodifiable(_selectedLoopTrackIds);
  List<SongTrack> get songTracks => _songTracks;
  bool get isMergingToSongTrack => _activeSongTrackId != null;
  int? get selectedSongTrackId => _selectedSongTrackId;
  bool get hasPlayableSongTracks => _songTracks.any((track) => track.hasAudio);
  int get longestPopulatedBarLength => _longestPopulatedBarLength();

  /// Bar length of the currently-selected (soloing) song track, or null when
  /// none is selected. Used by the UI to drive the playhead animation.
  int? get selectedSongTrackBarLength {
    final id = _selectedSongTrackId;
    if (id == null) return null;
    final idx = id - 100;
    if (idx < 0 || idx >= _songTracks.length) return null;
    return _songTracks[idx].barLength;
  }
  bool get fxEnabled => _fxEnabled;
  double get fxHighPassHz => _fxHighPassHz;
  double get fxLowPassHz => _fxLowPassHz;
  double get fxEqLowDb => _fxEqLowDb;
  double get fxEqMidDb => _fxEqMidDb;
  double get fxEqHighDb => _fxEqHighDb;
  double get fxCompressorAmount => _fxCompressorAmount;
  double get fxSaturationAmount => _fxSaturationAmount;
  int get fxDelayDivision => _fxDelayDivision;
  int get fxDelayFeel => _fxDelayFeel;
  double get fxDelayFeedback => _fxDelayFeedback;
  double get fxDelayInput => _fxDelayInput;
  double get fxReverbRoomSize => _fxReverbRoomSize;
  double get fxReverbDamping => _fxReverbDamping;
  double get fxLimiterCeilingDb => _fxLimiterCeilingDb;
  double get fxMasterOutputDb => _fxMasterOutputDb;
  List<double> get fxTrackOutputDb =>
      List<double>.unmodifiable(_fxTrackOutputDb);

  int get visualBarDividers =>
      _state.tracks.any((track) => track.barLength == 8) ? 8 : 4;

  bool get canStartRecording =>
      _state.transportState == TransportState.recording ||
      _state.transportState == TransportState.countIn ||
      _selectedLoopTrackIds.isNotEmpty;

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

  // ── Song track merge ───────────────────────────────────────────────────

  /// Starts a merge-to-song-track operation.
  /// Returns true if merge was successfully started, false if all song
  /// track slots are full or there are no loop tracks with audio.
  Future<bool> mergeToNextSongTrack() async {
    final native = _native;
    if (native == null) return false;

    // Must have recorded loop tracks to merge.
    if (!_state.hasRecordedTracks) return false;

    // Already merging — don't queue another.
    if (_activeSongTrackId != null) return false;

    // Find first free song track.
    SongTrack? target;
    for (final st in _songTracks) {
      if (!st.hasAudio) {
        target = st;
        break;
      }
    }
    if (target == null) return false;

    final int nativeIdx = target.id - 100;
    final int cycleBars = _longestPopulatedBarLength();
    final int spb = await native.engine.samplesPerBeat();
    final int loopLengthFrames = cycleBars * _beatsPerBar * spb;
    if (loopLengthFrames <= 0) return false;

    // Mark as capturing so the UI shows the blink animation.
    _activeSongTrackId = target.id;
    _updateSongTrack(target.id, (st) => st.copyWith(isCapturing: true));

    // Offline render: runs on a Kotlin background thread, awaited here.
    // The audio callback continues uninterrupted — both threads only READ
    // the loop track buffers.
    final bool ok = await native.renderMixToSongTrack(
      songTrackId: nativeIdx,
      loopLengthFrames: loopLengthFrames,
    );

    if (!ok || _activeSongTrackId != target.id) {
      // Aborted (transport cleared) or render failed.
      _activeSongTrackId = null;
      _updateSongTrack(target.id, (st) => st.copyWith(isCapturing: false));
      return false;
    }

    // Fetch waveform peaks and commit.
    final int bucketCount = cycleBars * _waveformBucketsPerBar;
    final List<double> peaks = await native.songTrackWaveformPeaks(
      songTrackId: nativeIdx,
      bucketCount: bucketCount,
    );

    _activeSongTrackId = null;
    _updateSongTrack(
      target.id,
      (st) => st.copyWith(
        hasAudio: true,
        isCapturing: false,
        isMuted: true,
        waveformPeaks: peaks,
        barLength: cycleBars,
      ),
    );
    return true;
  }

  // ---------------------------------------------------------------------------
  // Song track solo logic
  //
  // States:
  //   _selectedSongTrackId  — the track currently playing solo (or null)
  //   _pendingSongTrackChange — a quantized change is staged for loop restart
  //   _pendingSongTrackId   — the target at loop restart:
  //                             a real id  → switch to / enter that solo
  //                             null       → exit solo, restore 6 tracks
  //   _savedLoopMuteStates  — loop track mutes saved on first solo entry;
  //                           held until solo is fully exited
  // ---------------------------------------------------------------------------

  void toggleSongTrackMute(int songTrackId) {
    final int nativeIdx = songTrackId - 100;
    if (nativeIdx < 0 || nativeIdx >= _songTracks.length) return;
    if (!_songTracks[nativeIdx].hasAudio) return;

    final bool isPlaying =
        _state.transportState == TransportState.playing ||
        _state.transportState == TransportState.recording;

    if (!isPlaying) {
      // Immediate: no quantization needed when transport is stopped.
      if (_selectedSongTrackId == songTrackId) {
        _immediateSongTrackDeselect();
      } else {
        _immediateSongTrackSelect(songTrackId);
      }
      return;
    }

    // Quantized: stage the change; commit at loop restart.
    _stageSongTrackChange(songTrackId);
  }

  // --- Immediate (transport stopped) ------------------------------------------

  void _immediateSongTrackSelect(int songTrackId) {
    // Save loop mute states only on first entry into song track mode.
    if (_selectedSongTrackId == null) {
      _savedLoopMuteStates = _state.tracks.map((t) => t.isMuted).toList();
      _muteAllLoopTracks();
    }
    // Stop any previously-soloing track (no native audio when stopped).
    _selectedSongTrackId = songTrackId;
    _refreshSongTrackUI();
    notifyListeners();
  }

  void _immediateSongTrackDeselect() {
    _selectedSongTrackId = null;
    _restoreLoopMutes();
    // _restoreLoopMutes calls notifyListeners.
  }

  // --- Quantized (transport running) ------------------------------------------

  void _stageSongTrackChange(int songTrackId) {
    if (_pendingSongTrackChange) {
      // A change is already staged.
      if (_pendingSongTrackId == songTrackId) {
        // Tapping the pending track again cancels the pending change.
        _clearPending();
        return;
      }
      // Replace with new target (or deselect if tapping the live track).
    }

    if (songTrackId == _selectedSongTrackId) {
      // Arm the current solo for deselect.
      _pendingSongTrackChange = true;
      _pendingSongTrackId = null;
    } else {
      // Arm a new song track for solo.
      _pendingSongTrackChange = true;
      _pendingSongTrackId = songTrackId;
    }
    _refreshSongTrackUI();
    _startArmedBlink();
    // If the downbeat timer is not running (e.g., we are in recording state
    // and _startPlayback was never called), start it now so the commit fires.
    if (_songTrackDownbeatTimer == null) {
      _startDownbeatTimer();
    }
    final int token = ++_songTrackScheduleToken;
    unawaited(_schedulePendingSongTrackSwitch(token));
    notifyListeners();
  }

  /// Called by the downbeat timer at each loop restart.
  Future<void> _commitPendingSongTrackChange() async {
    if (!_pendingSongTrackChange) return;
    final int? targetId = _pendingSongTrackId;
    _clearPending(cancelNative: false);

    if (_pendingSongTrackScheduledNatively) {
      _pendingSongTrackScheduledNatively = false;
      if (targetId == null) {
        if (_selectedSongTrackId != null) {
          _selectedSongTrackId = null;
        }
        _restoreLoopMutes();
      } else {
        if (_selectedSongTrackId == null) {
          _savedLoopMuteStates = _state.tracks.map((t) => t.isMuted).toList();
          _muteAllLoopTracks();
        }
        _selectedSongTrackId = targetId;
        _refreshSongTrackUI();
        notifyListeners();
      }
      return;
    }

    if (targetId == null) {
      // Exit solo: stop playing song track, restore 6 tracks.
      if (_selectedSongTrackId != null) {
        unawaited(_native?.stopSongTrackPlayback(_selectedSongTrackId! - 100));
        _selectedSongTrackId = null;
      }
      _restoreLoopMutes(); // calls notifyListeners
    } else {
      // Enter solo or switch between song tracks.
      if (_selectedSongTrackId == null) {
        // First entry: save and mute 6 tracks.
        _savedLoopMuteStates = _state.tracks.map((t) => t.isMuted).toList();
        await _muteAllLoopTracksNative();
      } else if (_selectedSongTrackId != targetId) {
        // Switch: stop the current track, keep 6 tracks muted.
        unawaited(_native?.stopSongTrackPlayback(_selectedSongTrackId! - 100));
      }
      _selectedSongTrackId = targetId;
      await _native?.startSongTrackPlayback(targetId - 100);
      _refreshSongTrackUI();
      notifyListeners();
    }
  }

  void _clearPending({bool cancelNative = true}) {
    _pendingSongTrackChange = false;
    _pendingSongTrackId = null;
    _songTrackScheduleToken++;
    if (cancelNative) {
      _pendingSongTrackScheduledNatively = false;
      unawaited(
        _native?.cancelScheduledSongTrackSwitch() ?? Future<void>.value(),
      );
    }
    _stopArmedBlink();
  }

  Future<void> _schedulePendingSongTrackSwitch(int token) async {
    final native = _native;
    if (native == null) return;
    if (!_pendingSongTrackChange) return;
    final int? targetId = _pendingSongTrackId;
    final int anchor = _playbackAnchorFrame ?? 0;
    if (anchor <= 0) return;

    final int spb = await native.engine.samplesPerBeat();
    final int now = await native.engine.currentFrame();
    final int cycleBars = _longestPopulatedBarLength();
    final int masterCycleFrames = cycleBars * _beatsPerBar * spb;
    if (masterCycleFrames <= 0) return;

    int switchFrame =
        anchor + (((now - anchor) ~/ masterCycleFrames) + 1) * masterCycleFrames;
    if (switchFrame <= now) {
      switchFrame += masterCycleFrames;
    }
    if (token != _songTrackScheduleToken || !_pendingSongTrackChange) return;

    await native.scheduleSongTrackSwitch(
      songTrackId: targetId == null ? -1 : targetId - 100,
      startFrame: switchFrame,
    );
    if (token != _songTrackScheduleToken || !_pendingSongTrackChange) {
      await native.cancelScheduledSongTrackSwitch();
      return;
    }
    _pendingSongTrackScheduledNatively = true;
  }

  // --- Shared helpers ---------------------------------------------------------

  /// Mute all loop tracks that are currently unmuted (saves gain for restore).
  void _muteAllLoopTracks() {
    final List<Track> muted = List<Track>.from(_state.tracks);
    final native = _native;
    for (int i = 0; i < muted.length; i++) {
      final track = muted[i];
      if (!track.isMuted) {
        unawaited(native?.setTrackForceMuted(trackId: track.id, muted: true));
        muted[i] = track.copyWith(isMuted: true);
      }
    }
    _state = _state.copyWith(tracks: List.unmodifiable(muted));
  }

  /// Same as [_muteAllLoopTracks], but waits for the native gain updates so a
  /// song-track start cannot race ahead of the loop-track mute at a switch.
  Future<void> _muteAllLoopTracksNative() async {
    final List<Track> muted = List<Track>.from(_state.tracks);
    final native = _native;
    for (int i = 0; i < muted.length; i++) {
      final track = muted[i];
      if (!track.isMuted) {
        await native?.setTrackForceMuted(trackId: track.id, muted: true);
        muted[i] = track.copyWith(isMuted: true);
      }
    }
    _state = _state.copyWith(tracks: List.unmodifiable(muted));
  }

  /// Rebuild song track isMuted / isArmedForSolo / isArmedForDeselect flags.
  void _refreshSongTrackUI() {
    _songTracks = List<SongTrack>.unmodifiable(
      _songTracks.map((st) {
        final bool isLive = st.id == _selectedSongTrackId;
        final bool armedSolo =
            _pendingSongTrackChange && _pendingSongTrackId == st.id;
        final bool armedDeselect =
            _pendingSongTrackChange &&
            _pendingSongTrackId == null &&
            st.id == _selectedSongTrackId;
        return st.copyWith(
          isMuted: !isLive,
          isArmedForSolo: armedSolo,
          isArmedForDeselect: armedDeselect,
        );
      }).toList(growable: false),
    );
  }

  /// Restore loop track mute states saved before entering song track solo.
  void _restoreLoopMutes() {
    final saved = _savedLoopMuteStates;
    _savedLoopMuteStates = null;

    // Clear all armed / solo flags on song tracks.
    _songTracks = List<SongTrack>.unmodifiable(
      _songTracks.map((st) => st.copyWith(
            isMuted: true,
            isArmedForSolo: false,
            isArmedForDeselect: false,
          )).toList(growable: false),
    );

    if (saved == null) {
      notifyListeners();
      return;
    }

    final List<Track> restored = List<Track>.from(_state.tracks);
    final native = _native;
    for (int i = 0; i < restored.length; i++) {
      final track = restored[i];
      if (track.id < saved.length && !saved[track.id]) {
        unawaited(native?.setTrackForceMuted(trackId: track.id, muted: false));
        restored[i] = track.copyWith(isMuted: false);
      }
    }
    _state = _state.copyWith(tracks: List.unmodifiable(restored));
    notifyListeners();
  }

  Future<void> _syncNativeLoopForceMutePolicy() async {
    final native = _native;
    if (native == null) return;
    final bool shouldForceMuteLoops =
        _selectedSongTrackId != null ||
        (_headphoneSafetyEnabled && (_recordArmed || _isCaptureInProgress));
    for (final track in _state.tracks) {
      await native.setTrackForceMuted(
        trackId: track.id,
        muted: shouldForceMuteLoops,
      );
    }
  }

  Future<void> clearSongTrackAudio(int songTrackId) async {
    final int nativeIdx = songTrackId - 100;
    if (nativeIdx < 0 || nativeIdx >= 3) return;
    // If this track is currently soloing, restore loop track mutes first.
    if (_selectedSongTrackId == songTrackId) {
      _selectedSongTrackId = null;
      _clearPending();
      _restoreLoopMutes();
    }
    await _native?.stopSongTrackPlayback(nativeIdx);
    await _native?.clearSongTrack(nativeIdx);
    _updateSongTrack(
      songTrackId,
      (st) => st.copyWith(
        hasAudio: false,
        isMuted: true,
        isCapturing: false,
        waveformPeaks: const <double>[],
      ),
    );
  }

  /// Public alias used by the UI long-press delete on song track cards.
  Future<void> clearSongTrack(int songTrackId) => clearSongTrackAudio(songTrackId);

  void _updateSongTrack(int songTrackId, SongTrack Function(SongTrack) update) {
    final int idx = songTrackId - 100;
    if (idx < 0 || idx >= _songTracks.length) return;
    final List<SongTrack> updated = List<SongTrack>.from(_songTracks);
    updated[idx] = update(updated[idx]);
    _songTracks = List<SongTrack>.unmodifiable(updated);
    notifyListeners();
  }

  List<int> _normalizeSelectedLoopTrackIds(Iterable<int> trackIds) {
    final List<int> normalized = trackIds
        .where((id) => id >= 0 && id < _state.tracks.length)
        .toSet()
        .toList(growable: false)
      ..sort();
    return List<int>.unmodifiable(normalized);
  }

  void selectTrack(int index) {
    if (index < 0 || index >= _state.tracks.length) return;
    if (_selectedLoopTrackIds.contains(index)) {
      if (_selectedLoopTrackIds.length == 1) {
        return;
      }
      final List<int> updated = _selectedLoopTrackIds
          .where((id) => id != index)
          .toList(growable: false);
      _selectedLoopTrackIds = _normalizeSelectedLoopTrackIds(updated);
      if (_state.selectedTrackIndex == index && updated.isNotEmpty) {
        _state = _state.copyWith(selectedTrackIndex: updated.first);
      }
      notifyListeners();
      return;
    }

    _selectedLoopTrackIds = _normalizeSelectedLoopTrackIds(
      <int>[..._selectedLoopTrackIds, index],
    );
    notifyListeners();
  }

  void setTrackBarLength(int trackId, int barLength) {
    _updateTrack(trackId, (track) => track.copyWith(barLength: barLength));
  }

  void toggleMute(int trackId) {
    if (trackId < 0 || trackId >= _state.tracks.length) {
      return;
    }
    final Track track = _state.tracks[trackId];
    if (!track.hasAudio) {
      return;
    }
    if (track.isMuted) {
      final double restore = (_preMuteTrackOutputDb[trackId] ?? 0.0).clamp(
        _trackMinOutputDb,
        _trackMaxOutputDb,
      );
      _preMuteTrackOutputDb[trackId] = null;
      _updateTrack(trackId, (t) => t.copyWith(isMuted: false));
      unawaited(_setTrackOutputGainInternal(trackId, restore));
      return;
    }

    _preMuteTrackOutputDb[trackId] = _fxTrackOutputDb[trackId];
    _updateTrack(trackId, (t) => t.copyWith(isMuted: true));
    unawaited(_setTrackOutputGainInternal(trackId, _trackMinOutputDb));
  }

  void toggleTrackDelaySend(int trackId) {
    if (trackId < 0 || trackId >= _state.tracks.length) return;
    final Track track = _state.tracks[trackId];
    final bool enabled = !track.delaySendEnabled;
    final double level = enabled
        ? (track.delaySendLevel > 0.001
              ? track.delaySendLevel
              : _defaultTrackDelaySendLevel)
        : 0.0;
    _updateTrack(
      trackId,
      (t) => t.copyWith(delaySendEnabled: enabled, delaySendLevel: level),
    );
    final native = _native;
    if (native != null) {
      unawaited(native.setTrackDelaySendLevel(trackId: trackId, level: level));
    }
  }

  void toggleTrackReverbSend(int trackId) {
    if (trackId < 0 || trackId >= _state.tracks.length) return;
    final Track track = _state.tracks[trackId];
    final bool enabled = !track.reverbSendEnabled;
    final double level = enabled
        ? (track.reverbSendLevel > 0.001
              ? track.reverbSendLevel
              : _defaultTrackReverbSendLevel)
        : 0.0;
    _updateTrack(
      trackId,
      (t) => t.copyWith(reverbSendEnabled: enabled, reverbSendLevel: level),
    );
    final native = _native;
    if (native != null) {
      unawaited(native.setTrackReverbSendLevel(trackId: trackId, level: level));
    }
  }

  void setTrackDelaySendLevel(int trackId, double value) {
    if (trackId < 0 || trackId >= _state.tracks.length) return;
    final double clamped = value.clamp(0.0, 1.0);
    _updateTrack(
      trackId,
      (t) => t.copyWith(
        delaySendLevel: clamped,
        delaySendEnabled: clamped > 0.001,
      ),
    );
    final native = _native;
    if (native != null) {
      unawaited(
        native.setTrackDelaySendLevel(trackId: trackId, level: clamped),
      );
    }
  }

  void setTrackReverbSendLevel(int trackId, double value) {
    if (trackId < 0 || trackId >= _state.tracks.length) return;
    final double clamped = value.clamp(0.0, 1.0);
    _updateTrack(
      trackId,
      (t) => t.copyWith(
        reverbSendLevel: clamped,
        reverbSendEnabled: clamped > 0.001,
      ),
    );
    final native = _native;
    if (native != null) {
      unawaited(
        native.setTrackReverbSendLevel(trackId: trackId, level: clamped),
      );
    }
  }

  Future<void> toggleHeadphoneSafetyMode() async {
    _headphoneSafetyEnabled = !_headphoneSafetyEnabled;
    notifyListeners();

    await _syncNativeLoopForceMutePolicy();

    if (_headphoneSafetyEnabled) {
      if (_isCaptureInProgress) {
        await _audioService.stopAll();
      }
      return;
    }

    if (_state.transportState == TransportState.playing ||
        _state.transportState == TransportState.recording ||
        _recordArmed) {
      await _playAudibleTracks(_state.tracks);
    }
  }

  Future<void> setFxEnabled(bool enabled) async {
    _fxEnabled = enabled;
    notifyListeners();
    await _applyMasterOutputGain();
  }

  Future<void> setFxHighPassHz(double value) async {
    _fxHighPassHz = value.clamp(20.0, 1000.0);
    notifyListeners();
    await _applyHighPass();
  }

  Future<void> setFxLowPassHz(double value) async {
    _fxLowPassHz = value.clamp(500.0, 20000.0);
    notifyListeners();
    await _applyLowPass();
  }

  Future<void> setFxEqLowDb(double value) async {
    _fxEqLowDb = value.clamp(-24.0, 12.0);
    notifyListeners();
    await _applyEqLow();
  }

  Future<void> setFxEqMidDb(double value) async {
    _fxEqMidDb = value.clamp(-24.0, 12.0);
    notifyListeners();
    await _applyEqMid();
  }

  Future<void> setFxEqHighDb(double value) async {
    _fxEqHighDb = value.clamp(-24.0, 12.0);
    notifyListeners();
    await _applyEqHigh();
  }

  void setFxCompressorAmount(double value) {
    _fxCompressorAmount = value.clamp(0.0, 1.0);
    notifyListeners();
    unawaited(_applyCompressorAmount());
  }

  void setFxSaturationAmount(double value) {
    _fxSaturationAmount = value.clamp(0.0, 1.0);
    notifyListeners();
    unawaited(_applySaturationAmount());
  }

  void setFxDelayDivision(int value) {
    const List<int> allowed = <int>[2, 4, 8, 16];
    _fxDelayDivision = allowed.contains(value) ? value : 8;
    notifyListeners();
    unawaited(_applyDelayDivision());
  }

  void setFxDelayFeel(int value) {
    const List<int> allowed = <int>[0, 1, 2];
    _fxDelayFeel = allowed.contains(value) ? value : 0;
    notifyListeners();
    unawaited(_applyDelayFeel());
  }

  void setFxDelayFeedback(double value) {
    _fxDelayFeedback = value.clamp(0.0, 0.95);
    notifyListeners();
    unawaited(_applyDelayFeedback());
  }

  void setFxDelayInput(double value) {
    _fxDelayInput = value.clamp(0.0, 1.0);
    notifyListeners();
    unawaited(_applyDelayInput());
  }

  void setFxReverbRoomSize(double value) {
    _fxReverbRoomSize = value.clamp(0.0, 1.0);
    notifyListeners();
    unawaited(_applyReverbRoomSize());
  }

  void setFxReverbDamping(double value) {
    _fxReverbDamping = value.clamp(0.0, 1.0);
    notifyListeners();
    unawaited(_applyReverbDamping());
  }

  Future<void> setFxLimiterCeilingDb(double value) async {
    _fxLimiterCeilingDb = value.clamp(-24.0, -0.1);
    notifyListeners();
    await _applyLimiterCeiling();
  }

  Future<void> setFxMasterOutputDb(double value) async {
    _fxMasterOutputDb = value.clamp(-24.0, 12.0);
    notifyListeners();
    await _applyMasterOutputGain();
  }

  Future<void> setTrackOutputGainDb(int trackId, double value) async {
    if (trackId < 0 || trackId >= _fxTrackOutputDb.length) {
      return;
    }
    final double clamped = value.clamp(_trackMinOutputDb, _trackMaxOutputDb);
    final bool shouldMute =
        (clamped - _trackMinOutputDb).abs() <= _muteThreshold;
    final bool isMuted = _state.tracks[trackId].isMuted;

    // Minimum mixer gain means muted, including manual mixer moves.
    if (!isMuted && shouldMute) {
      _preMuteTrackOutputDb[trackId] = _fxTrackOutputDb[trackId];
      _updateTrack(trackId, (t) => t.copyWith(isMuted: true));
    }

    // If a muted track is moved above silence in the mixer, unmute it.
    if (isMuted && !shouldMute) {
      _preMuteTrackOutputDb[trackId] = null;
      _updateTrack(trackId, (t) => t.copyWith(isMuted: false));
    }

    await _setTrackOutputGainInternal(trackId, clamped);
  }

  Future<void> _setTrackOutputGainInternal(int trackId, double db) async {
    _fxTrackOutputDb[trackId] = db;
    notifyListeners();
    final native = _native;
    if (native == null) return;
    await native.setTrackOutputGainDb(trackId: trackId, db: db);
  }

  Future<void> resetAllFx() async {
    _fxEnabled = true;
    _fxHighPassHz = 20.0;
    _fxLowPassHz = 20000.0;
    _fxEqLowDb = 0.0;
    _fxEqMidDb = 0.0;
    _fxEqHighDb = 0.0;
    _fxCompressorAmount = 0.0;
    _fxSaturationAmount = 0.0;
    _fxDelayDivision = 8;
    _fxDelayFeel = 0;
    _fxDelayFeedback = 0.4;
    _fxDelayInput = 0.85;
    _fxReverbRoomSize = 0.5;
    _fxReverbDamping = 0.55;
    _fxLimiterCeilingDb = -1.0;
    _fxMasterOutputDb = 0.0;
    for (int i = 0; i < _fxTrackOutputDb.length; i++) {
      _fxTrackOutputDb[i] = 0.0;
      _preMuteTrackOutputDb[i] = null;
    }
    notifyListeners();
    await _applyMasterOutputGain();
    await _applyLimiterCeiling();
    await _applyHighPass();
    await _applyLowPass();
    await _applyEqLow();
    await _applyEqMid();
    await _applyEqHigh();
    await _applyCompressorAmount();
    await _applySaturationAmount();
    await _applyDelayDivision();
    await _applyDelayFeel();
    await _applyDelayFeedback();
    await _applyDelayInput();
    await _applyReverbRoomSize();
    await _applyReverbDamping();
    final native = _native;
    if (native != null) {
      for (int i = 0; i < _fxTrackOutputDb.length; i++) {
        await native.setTrackOutputGainDb(trackId: i, db: 0.0);
      }
    }
  }

  Future<void> _applyMasterOutputGain() async {
    final native = _native;
    if (native == null) return;
    final double db = _fxEnabled ? _fxMasterOutputDb : 0.0;
    await native.setMasterOutputGainDb(db);
  }

  Future<void> _applyLimiterCeiling() async {
    final native = _native;
    if (native == null) return;
    await native.setLimiterCeilingDb(_fxLimiterCeilingDb);
  }

  Future<void> _applyHighPass() async {
    final native = _native;
    if (native == null) return;
    await native.setHighPassHz(_fxHighPassHz);
  }

  Future<void> _applyLowPass() async {
    final native = _native;
    if (native == null) return;
    await native.setLowPassHz(_fxLowPassHz);
  }

  Future<void> _applyEqLow() async {
    final native = _native;
    if (native == null) return;
    await native.setEqLowDb(_fxEqLowDb);
  }

  Future<void> _applyEqMid() async {
    final native = _native;
    if (native == null) return;
    await native.setEqMidDb(_fxEqMidDb);
  }

  Future<void> _applyEqHigh() async {
    final native = _native;
    if (native == null) return;
    await native.setEqHighDb(_fxEqHighDb);
  }

  Future<void> _applyCompressorAmount() async {
    final native = _native;
    if (native == null) return;
    await native.setCompressorAmount(_fxCompressorAmount);
  }

  Future<void> _applySaturationAmount() async {
    final native = _native;
    if (native == null) return;
    await native.setSaturationAmount(_fxSaturationAmount);
  }

  Future<void> _applyDelayDivision() async {
    final native = _native;
    if (native == null) return;
    await native.setDelayDivision(_fxDelayDivision);
  }

  Future<void> _applyDelayFeel() async {
    final native = _native;
    if (native == null) return;
    await native.setDelayFeel(_fxDelayFeel);
  }

  Future<void> _applyDelayFeedback() async {
    final native = _native;
    if (native == null) return;
    await native.setDelayFeedback(_fxDelayFeedback);
  }

  Future<void> _applyDelayInput() async {
    final native = _native;
    if (native == null) return;
    await native.setDelayInput(_fxDelayInput);
  }

  Future<void> _applyReverbRoomSize() async {
    final native = _native;
    if (native == null) return;
    await native.setReverbRoomSize(_fxReverbRoomSize);
  }

  Future<void> _applyReverbDamping() async {
    final native = _native;
    if (native == null) return;
    await native.setReverbDamping(_fxReverbDamping);
  }

  Future<void> playAll() async {
    if (_state.transportState == TransportState.countIn) {
      await _cancelCountIn();
      return;
    }

    if (_state.transportState == TransportState.stopped) {
      if (!_state.hasRecordedTracks && !hasPlayableSongTracks) {
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
    final native = _native;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _armStartTimer?.cancel();
    _armStartTimer = null;
    _stopArmedBlink();
    _stopDownbeatTimer();
    _pendingSongTrackChange = false;
    _pendingSongTrackId = null;
    _pendingSongTrackScheduledNatively = false;
    await native?.cancelScheduledSongTrackSwitch();
    _recordArmed = false;
    _armedTrackId = null;
    await _syncNativeLoopForceMutePolicy();
    await _stopBeatListener();
    _beatFlash = false;
    _localBeat = 0;
    _countInBaseBeat = null;
    _playbackAnchorFrame = null;
    _resetRecordingSequenceState();

    // Abort any in-progress song track merge. Clear _activeSongTrackId so
    // the awaited renderMixToSongTrack call detects the abort and does not
    // commit the result.
    if (_activeSongTrackId != null) {
      final int nativeIdx = _activeSongTrackId! - 100;
      await _native?.clearSongTrack(nativeIdx);
      _updateSongTrack(
        _activeSongTrackId!,
        (st) => st.copyWith(isCapturing: false),
      );
      _activeSongTrackId = null;
    }

    await _audioService.stopAll(); // also stops song track native playback

    // Keep _selectedSongTrackId and _savedLoopMuteStates intact so that when
    // the user presses play again the same song track resumes and loop tracks
    // stay muted.  Just clear any pending quantized-change armed state.
    // Native audio has already been stopped by _audioService.stopAll() above.
    _pendingSongTrackChange = false;
    _pendingSongTrackId = null;

    // Clear only armed flags; preserve isMuted so the selected song track
    // continues to show as "selected" (isMuted=false) while stopped.
    final List<SongTrack> stoppedSongTracks = _songTracks
        .map((st) => st.copyWith(
              isArmedForSolo: false,
              isArmedForDeselect: false,
            ))
        .toList(growable: false);
    _songTracks = List<SongTrack>.unmodifiable(stoppedSongTracks);

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

    final List<int> targets = _selectedRecordingTargets();
    if (targets.isEmpty) {
      return;
    }

    if (_state.transportState == TransportState.playing) {
      await _armSelectedTracksOnNextMasterBoundary(targets);
      return;
    }

    if (targets.first != _state.selectedTrackIndex) {
      _state = _state.copyWith(selectedTrackIndex: targets.first);
      notifyListeners();
    }

    _activeRecordingTrackIds
      ..clear()
      ..addAll(targets);

    await _startCountIn(targets);
  }

  List<int> _selectedRecordingTargets() {
    final List<int> valid = _normalizeSelectedLoopTrackIds(
      _selectedLoopTrackIds,
    );
    if (valid.isNotEmpty) {
      return valid;
    }
    final int selected = _state.selectedTrackIndex;
    if (selected >= 0 && selected < _state.tracks.length) {
      return <int>[selected];
    }
    return const <int>[];
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
    );
    notifyListeners();

    final int spb = await native.engine.samplesPerBeat();
    final int sampleRate = await native.engine.sampleRate();
    final int now = await native.engine.currentFrame();

    final int targetBars = _state.tracks[trackId].barLength;
    final int cycleBars = _longestPopulatedBarLength();
    final int masterCycleFrames = cycleBars * _beatsPerBar * spb;
    final int anchor = _playbackAnchorFrame ?? now;
    int startFrame =
        anchor +
        (((now - anchor) ~/ masterCycleFrames) + 1) * masterCycleFrames;
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
    if (_headphoneSafetyEnabled) {
      await native.setMetronomeAudible(false);
    }
    _beatSub = native.beatStream.listen(_onNativeBeat);
    await native.startMetronome();
    if (_headphoneSafetyEnabled) {
      await native.setMetronomeAudible(false);
    }

    final int msUntilStart = (((startFrame - now) * 1000) / sampleRate)
        .round()
        .clamp(0, 1 << 30);

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

      if (_headphoneSafetyEnabled) {
        unawaited(_syncNativeLoopForceMutePolicy());
        unawaited(_audioService.stopAll());
      }
    });

    _recordingTimer?.cancel();
    _recordingTimer = Timer(
      Duration(
        milliseconds:
            msUntilStart + ((lengthFrames * 1000) / sampleRate).round(),
      ),
      () => _stopRecording(continuePlayback: true),
    );

    // Anchor for future loop-phase alignment: the native engine begins the
    // new track's playback loop precisely at startFrame + lengthFrames.
    _playbackAnchorFrame = startFrame + lengthFrames;
  }

  Future<void> _armSelectedTracksOnNextMasterBoundary(List<int> targets) async {
    if (targets.isEmpty) return;
    if (targets.length == 1) {
      await _armSingleTrackOnNextMasterBoundary(targets.first);
      return;
    }

    final native = _native;
    if (native == null) return;

    _activeRecordingTrackIds
      ..clear()
      ..addAll(targets);

    _recordArmed = true;
    _armedTrackId = targets.first;
    _suppressMetronomeClicks = true;
    _startArmedBlink();

    final List<Track> armedTracks = _state.tracks
        .map(
          (track) => track.id == targets.first
              ? track.copyWith(state: TrackState.armed)
              : track.hasAudio
              ? track.copyWith(state: TrackState.looping)
              : track.copyWith(state: TrackState.empty),
        )
        .toList(growable: false);
    _state = _state.copyWith(
      tracks: armedTracks,
      selectedTrackIndex: targets.first,
      transportState: TransportState.playing,
    );
    notifyListeners();

    final int spb = await native.engine.samplesPerBeat();
    final int sampleRate = await native.engine.sampleRate();
    final int now = await native.engine.currentFrame();
    final int cycleBars = _longestPopulatedBarLength();
    final int masterCycleFrames = cycleBars * _beatsPerBar * spb;
    final int anchor = _playbackAnchorFrame ?? now;
    int firstStartFrame =
        anchor +
        (((now - anchor) ~/ masterCycleFrames) + 1) * masterCycleFrames;
    if (firstStartFrame <= now) {
      firstStartFrame += masterCycleFrames;
    }

    int currentStart = firstStartFrame;
    int totalLengthFrames = 0;
    final List<int> startFrames = <int>[];
    for (int i = 0; i < targets.length; i++) {
      final int trackIndex = targets[i];
      final int barLen = _state.tracks[trackIndex].barLength;
      final int lengthFrames = spb * barLen * _beatsPerBar;
      await native.engine.armRecording(
        trackId: trackIndex,
        startFrame: currentStart,
        lengthFrames: lengthFrames,
      );
      startFrames.add(currentStart);
      currentStart += lengthFrames;
      totalLengthFrames += lengthFrames;
      if (i < targets.length - 1 && _state.repeatCount > 0) {
        final int repeatDelayBeats = _state.repeatCount * barLen * _beatsPerBar;
        final int repeatDelayFrames = repeatDelayBeats * spb;
        currentStart += repeatDelayFrames;
        totalLengthFrames += repeatDelayFrames;
      }
    }

    _recordingSequenceTargets = List<int>.from(targets);
    _recordingSequenceStartBeats = const <int>[];
    _recordingSequenceCurrentIdx = 0;

    _clearRecordingSequenceUiTimers();
    for (int i = 1; i < targets.length; i++) {
      final int delayMs = (((startFrames[i] - now) * 1000) / sampleRate)
          .round()
          .clamp(0, 1 << 30);
      _recordingSequenceUiTimers.add(
        Timer(Duration(milliseconds: delayMs), () {
          if (_state.transportState != TransportState.recording) return;
          _switchRecordingSequenceUiTarget(i);
        }),
      );
    }

    await native.setTempoBpm(_state.bpm.toDouble());
    if (_headphoneSafetyEnabled) {
      await native.setMetronomeAudible(false);
    }
    _beatSub = native.beatStream.listen(_onNativeBeat);
    await native.startMetronome();
    if (_headphoneSafetyEnabled) {
      await native.setMetronomeAudible(false);
    }

    final int msUntilStart = (((firstStartFrame - now) * 1000) / sampleRate)
        .round()
        .clamp(0, 1 << 30);
    final int firstTrackId = targets.first;
    _armStartTimer?.cancel();
    _armStartTimer = Timer(Duration(milliseconds: msUntilStart), () {
      if (!_recordArmed || _armedTrackId != firstTrackId) return;
      _recordArmed = false;
      _armedTrackId = null;
      _stopArmedBlink();

      final List<Track> tracks = _state.tracks
          .map(
            (track) => track.id == firstTrackId
                ? track.copyWith(state: TrackState.recording)
                : track,
          )
          .toList(growable: false);
      _state = _state.copyWith(
        tracks: tracks,
        transportState: TransportState.recording,
      );
      notifyListeners();

      if (_headphoneSafetyEnabled) {
        unawaited(_syncNativeLoopForceMutePolicy());
        unawaited(_audioService.stopAll());
      }
    });

    _recordingTimer?.cancel();
    _recordingTimer = Timer(
      Duration(
        milliseconds:
            msUntilStart + ((totalLengthFrames * 1000) / sampleRate).round(),
      ),
      () => _stopRecording(continuePlayback: true),
    );

    final int firstTargetBars = _state.tracks[targets.first].barLength;
    _playbackAnchorFrame =
        firstStartFrame + (firstTargetBars * _beatsPerBar * spb);
  }

  int _longestPopulatedBarLength() {
    int longest = 1;
    for (final t in _state.tracks) {
      final bool isPopulated =
          t.hasAudio ||
          t.state == TrackState.playing ||
          t.state == TrackState.looping ||
          t.state == TrackState.recording;
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
    _resetRecordingSequenceState();
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

  void _resetRecordingSequenceState() {
    _clearRecordingSequenceUiTimers();
    _recordingSequenceTargets = const [];
    _recordingSequenceStartBeats = const [];
    _recordingSequenceCurrentIdx = 0;
  }

  /// Start a periodic timer that fires at each master loop downbeat so pending
  /// song track changes can be committed in sync. Must be called after the
  /// transport starts playing, once the cycle length is known.
  void _startDownbeatTimer() {
    _songTrackDownbeatTimer?.cancel();
    final int bars = _longestPopulatedBarLength();
    final int bpm = _state.bpm;
    final int ms = ((bars * _beatsPerBar * 60000) / bpm).round();
    final Duration period = Duration(milliseconds: ms.clamp(250, 120000));
    // Fire once at the next downbeat, then repeat.
    _songTrackDownbeatTimer = Timer(period, () {
      _onDownbeat();
      _songTrackDownbeatTimer = Timer.periodic(period, (_) => _onDownbeat());
    });
  }

  void _stopDownbeatTimer() {
    _songTrackDownbeatTimer?.cancel();
    _songTrackDownbeatTimer = null;
  }

  void _onDownbeat() {
    if (_pendingSongTrackChange) {
      unawaited(_commitPendingSongTrackChange());
    }
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
      debugPrint(
        '[LooperProvider] no NativeAudioService; count-in visual only',
      );
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
        // sample. If headphone-safety is enabled, mute the metronome NOW so
        // the upcoming recording downbeat is silent; if we wait until beat 5,
        // that click has already played. We DON'T flip the UI state here; that
        // would start the playhead a full beat before the audio downbeat.
        if (_headphoneSafetyEnabled) {
          unawaited(_native?.setMetronomeAudible(false) ?? Future<void>.value());
        }
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
      _advanceRecordingSequenceIfNeeded();
      for (final trackId in _activeRecordingTrackIds) {
        unawaited(_refreshTrackWaveform(trackId));
      }
    }
  }

  /// If this beat has moved us into the next target's recording window,
  /// flip the previous target to "looping" and the new target to
  /// "recording". Called on every beat during a sequential recording pass.
  void _advanceRecordingSequenceIfNeeded() {
    if (_recordingSequenceUiTimers.isNotEmpty) return;
    if (_recordingSequenceTargets.length <= 1) return;
    final int nextIdx = _recordingSequenceCurrentIdx + 1;
    if (nextIdx >= _recordingSequenceTargets.length) return;
    if (_localBeat < _recordingSequenceStartBeats[nextIdx]) return;

    _switchRecordingSequenceUiTarget(nextIdx);
  }

  void _switchRecordingSequenceUiTarget(int nextIdx) {
    if (_recordingSequenceTargets.length <= 1) return;
    if (nextIdx <= _recordingSequenceCurrentIdx) return;
    if (nextIdx >= _recordingSequenceTargets.length) return;

    final int prevId = _recordingSequenceTargets[_recordingSequenceCurrentIdx];
    final int newId = _recordingSequenceTargets[nextIdx];
    _recordingSequenceCurrentIdx = nextIdx;

    final List<Track> updated = _state.tracks
        .map((track) {
          if (track.id == prevId) {
            // Native engine has already auto-started playback on this track.
            return track.copyWith(hasAudio: true, state: TrackState.looping);
          }
          if (track.id == newId) {
            return track.copyWith(state: TrackState.recording);
          }
          return track;
        })
        .toList(growable: false);

    _state = _state.copyWith(tracks: updated, selectedTrackIndex: newId);
    notifyListeners();

    if (_headphoneSafetyEnabled && _isCaptureInProgress) {
      unawaited(_audioService.stopAll());
    }
  }

  void _clearRecordingSequenceUiTimers() {
    for (final timer in _recordingSequenceUiTimers) {
      timer.cancel();
    }
    _recordingSequenceUiTimers.clear();
  }

  void _flipToRecordingState() {
    if (_recordingSequenceTargets.isEmpty) return;

    final int currentId = _recordingSequenceTargets[_recordingSequenceCurrentIdx];
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

    if (_headphoneSafetyEnabled) {
      unawaited(_syncNativeLoopForceMutePolicy());
      unawaited(_audioService.stopAll());
    }

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
    // position of each target's start/end so
    // _advanceRecordingSequenceIfNeeded() can flip UI states at the right
    // moment.
    final List<int> starts = <int>[];
    int currentStart = firstStartFrame;
    int localBeatCursor = 5; // beat 5 = first recording downbeat
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

    _recordingSequenceTargets = List<int>.from(targets);
    _recordingSequenceStartBeats = starts;
    _recordingSequenceCurrentIdx = 0;

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

    _state = _state.copyWith(
      selectedTrackIndex: _firstEmptyTrackIndex(),
    );
    notifyListeners();
  }

  Future<void> clearAllTracks() async {
    await clearLoopTracks();
    // Clear all three song tracks on native side.
    for (int i = 0; i < 3; i++) {
      await _native?.clearSongTrack(i);
    }
    _songTracks = List<SongTrack>.unmodifiable([
      SongTrack(id: 100, label: 'A'),
      SongTrack(id: 101, label: 'B'),
      SongTrack(id: 102, label: 'C'),
    ]);
    notifyListeners();
  }

  Future<void> clearLoopTracks() async {
    final native = _native;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _armStartTimer?.cancel();
    _armStartTimer = null;
    _stopArmedBlink();
    _stopDownbeatTimer();
    _pendingSongTrackChange = false;
    _pendingSongTrackId = null;
    _pendingSongTrackScheduledNatively = false;
    await native?.cancelScheduledSongTrackSwitch();
    _recordArmed = false;
    _armedTrackId = null;
    _suppressMetronomeClicks = false;
    _playbackAnchorFrame = null;
    await _stopBeatListener();
    _beatFlash = false;
    _localBeat = 0;
    _countInBaseBeat = null;
    _pendingTargets = const [];
    _resetRecordingSequenceState();
    _activeRecordingTrackIds.clear();

    // Clear any song track solo state without restoring mutes (all tracks are
    // being wiped, so restoring mute state is meaningless).
    _selectedSongTrackId = null;
    _savedLoopMuteStates = null;
    for (int i = 0; i < _preMuteTrackOutputDb.length; i++) {
      _preMuteTrackOutputDb[i] = null;
    }
    if (native != null) {
      for (final track in _state.tracks) {
        await native.setTrackForceMuted(trackId: track.id, muted: false);
      }
    }

    // Abort any in-progress merge.
    _activeSongTrackId = null;

    await _audioService.stopAll(); // also stops song track native playback

    for (final track in _state.tracks) {
      if (track.hasAudio) {
        await _audioService.deleteTrack(track.id);
      }
    }

    final List<Track> clearedTracks = _state.tracks
        .map(
          (track) => track.copyWith(
            hasAudio: false,
            isMuted: false,
            state: TrackState.empty,
            waveformPeaks: const <double>[],
          ),
        )
        .toList(growable: false);

    _state = _state.copyWith(
      tracks: clearedTracks,
      transportState: TransportState.stopped,
      selectedTrackIndex: 0,
    );
    notifyListeners();
  }

  Future<void> _startPlayback() async {
    if (!_state.hasRecordedTracks && _selectedSongTrackId == null) {
      for (final songTrack in _songTracks) {
        if (songTrack.hasAudio) {
          _selectedSongTrackId = songTrack.id;
          _refreshSongTrackUI();
          break;
        }
      }
    }

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

    // Start the downbeat timer so quantized song track changes fire in sync.
    _startDownbeatTimer();

    // If a song track is soloed, start its native playback now that the
    // transport is running.
    if (_selectedSongTrackId != null) {
      final int nativeIdx = _selectedSongTrackId! - 100;
      unawaited(_native?.startSongTrackPlayback(nativeIdx));
    }
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
    _resetRecordingSequenceState();

    if (_activeRecordingTrackIds.isEmpty) {
      _state = _state.copyWith(
        transportState: continuePlayback
            ? TransportState.playing
            : TransportState.stopped,
        selectedTrackIndex: _firstEmptyTrackIndex(),
      );
      notifyListeners();
      return;
    }

    final Set<int> finalizedTrackIds = Set<int>.from(_activeRecordingTrackIds);

    // When the user explicitly stops (continuePlayback=false), abort any
    // native recordings still in progress so the engine does not auto-start
    // playback after Dart has returned to the stopped state.
    // When the recording timer fires naturally (continuePlayback=true), native
    // has already completed, so stopTrackRecording is a no-op there.
    if (!continuePlayback) {
      for (final trackId in finalizedTrackIds) {
        await _audioService.stopTrackRecording(trackId);
      }
    }

    // Determine which tracks actually have captured audio (completed
    // recordings are kRecorded=3; aborted ones were cleared to kEmpty=0).
    final Set<int> actuallyRecordedIds = <int>{};
    for (final trackId in finalizedTrackIds) {
      if (await _audioService.hasRecordedAudio(trackId)) {
        actuallyRecordedIds.add(trackId);
      }
    }

    // Refresh waveform and normalise only for tracks with real audio.
    for (final trackId in actuallyRecordedIds) {
      await _refreshTrackWaveform(trackId);
      try {
        final native = _native;
        if (native != null) {
          final peaks = _state.tracks[trackId].waveformPeaks;
          if (peaks.isNotEmpty) {
            final double maxPeak = peaks.reduce((a, b) => a > b ? a : b);
            const double targetPeak = 0.95;
            if (maxPeak > 0.0001) {
              final double gainFactor = (targetPeak / maxPeak).clamp(0.01, 100.0);
              final double gainDb = 20.0 * (math.log(gainFactor) / math.ln10);
              final double clampedDb = gainDb.clamp(_trackMinOutputDb, _trackMaxOutputDb);
              await _setTrackOutputGainInternal(trackId, clampedDb);
            }
          }
        }
      } catch (err) {
        debugPrint('[LooperProvider] normalization failed for track $trackId: $err');
      }
    }

    final List<Track> updatedTracks = _state.tracks
        .map(
          (track) => finalizedTrackIds.contains(track.id)
              ? track.copyWith(
                  hasAudio: actuallyRecordedIds.contains(track.id),
                  state: actuallyRecordedIds.contains(track.id)
                      ? (continuePlayback ? TrackState.looping : TrackState.playing)
                      : TrackState.empty,
                )
              : track.hasAudio
              ? track.copyWith(
                  state: continuePlayback
                      ? TrackState.looping
                      : TrackState.playing,
                )
              : track.copyWith(state: TrackState.empty),
        )
        .toList(growable: false);

    _activeRecordingTrackIds.clear();

    _state = _state.copyWith(
      tracks: updatedTracks,
      transportState: continuePlayback
          ? TransportState.playing
          : TransportState.stopped,
      selectedTrackIndex: _nextEmptyTrackIndexAfter(
        _selectionAnchorTrackId(actuallyRecordedIds),
      ),
    );
    notifyListeners();

    await _syncNativeLoopForceMutePolicy();

    if (continuePlayback) {
      await _playAudibleTracks(updatedTracks, resetAnchor: true);
      // Start the downbeat timer so any pending (or future) song track changes
      // fire in sync.  _startPlayback() does this when playing from stopped,
      // but the recording-complete path bypasses _startPlayback(), so we must
      // start the timer here too.
      _startDownbeatTimer();
      // If a song track was soloed while recording, start its native playback
      // now that the transport has fully transitioned to playing.
      if (_selectedSongTrackId != null) {
        final int nativeIdx = _selectedSongTrackId! - 100;
        unawaited(_native?.startSongTrackPlayback(nativeIdx));
      }
    } else {
      _playbackAnchorFrame = null;
    }
  }

  Future<void> _playAudibleTracks(
    List<Track> tracks, {
    bool resetAnchor = false,
  }) async {
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
    for (final track in tracks.where(_isTrackAudibleInCurrentMode)) {
      await _audioService.playTrack(track.id, loop: true);
    }
  }

  bool get _isCaptureInProgress =>
      _state.transportState == TransportState.recording;

  bool _isTrackAudibleInCurrentMode(Track track) {
    if (!track.hasAudio || track.isMuted) {
      return false;
    }
    if (!_headphoneSafetyEnabled || !_isCaptureInProgress) {
      return true;
    }
    // Headphone safety mode: while capturing, keep all loop playback silent
    // so neither previously recorded material nor overwrite targets can leak
    // from the speaker back into the mic.
    return false;
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
    _updateTrack(trackId, (track) => track.copyWith(waveformPeaks: peaks));
  }

  void _updateTrack(int trackId, Track Function(Track) update) {
    final List<Track> updatedTracks = List<Track>.from(_state.tracks);
    updatedTracks[trackId] = update(updatedTracks[trackId]);
    _state = _state.copyWith(tracks: updatedTracks);
    notifyListeners();
  }

  int _firstEmptyTrackIndex() {
    final int idx = _state.tracks.indexWhere((t) => !t.hasAudio);
    return idx >= 0 ? idx : -1;
  }

  int _selectionAnchorTrackId(Set<int> finalizedTrackIds) {
    if (_recordingSequenceTargets.isNotEmpty) {
      return _recordingSequenceTargets.last;
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
    final int normalizedAnchor = anchorTrackId < 0
        ? 0
        : (anchorTrackId % trackCount);

    for (int step = 1; step <= trackCount; step++) {
      final int idx = (normalizedAnchor + step) % trackCount;
      if (!_state.tracks[idx].hasAudio) {
        return idx;
      }
    }

    return -1;
  }
}
