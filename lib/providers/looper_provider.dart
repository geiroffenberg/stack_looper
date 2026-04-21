import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../models/looper_state.dart';
import '../models/track.dart';
import '../services/audio_service.dart';

class LooperProvider extends ChangeNotifier {
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
  LooperState _state;
  final Set<int> _activeRecordingTrackIds = <int>{};

  LooperState get state => _state;

  int get visualBarDividers =>
      _state.tracks.any((track) => track.barLength == 8) ? 8 : 4;

  List<int> get availableNumTracksToRecordOptions {
    final int empty = _state.emptyTrackCount;
    if (empty <= 0) {
      return const [1];
    }
    return List<int>.generate(empty, (i) => i + 1);
  }

  bool get canStartRecording =>
      _state.transportState == TransportState.recording || _state.emptyTrackCount > 0;

  void setBpm(int bpm) {
    _state = _state.copyWith(
      bpm: bpm.clamp(AppConstants.minBpm, AppConstants.maxBpm),
    );
    notifyListeners();
  }

  void setRepeatCount(int repeatCount) {
    _state = _state.copyWith(repeatCount: repeatCount);
    notifyListeners();
  }

  void setNumTracksToRecord(int count) {
    final int maxSelectable = _maxSelectableTrackCount();
    _state = _state.copyWith(numTracksToRecord: count.clamp(1, maxSelectable));
    notifyListeners();
  }

  void selectTrack(int index) {
    if (index < 0 || index >= _state.tracks.length) {
      return;
    }
    _state = _state.copyWith(selectedTrackIndex: index);
    notifyListeners();
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
    );
    notifyListeners();
  }

  Future<void> startRecordingSession() async {
    if (_state.transportState == TransportState.recording) {
      await _stopRecording(continuePlayback: true);
      return;
    }

    if (_state.emptyTrackCount <= 0) {
      return;
    }

    final bool wasPlaying = _state.transportState == TransportState.playing;
    final targets = _targetTrackIndexes();
    if (targets.isEmpty) {
      return;
    }

    _activeRecordingTrackIds
      ..clear()
      ..addAll(targets);

    for (final trackIndex in targets) {
      final track = _state.tracks[trackIndex];
      await _audioService.startTrackRecording(track.id, track.barLength, _state.bpm);
    }

    final List<Track> updatedTracks = _state.tracks
        .map(
          (track) => _activeRecordingTrackIds.contains(track.id)
              ? track.copyWith(state: TrackState.recording)
              : track.hasAudio
                  ? track.copyWith(state: TrackState.looping)
                  : track.copyWith(state: TrackState.empty),
        )
        .toList(growable: false);

    _state = _state.copyWith(
      tracks: updatedTracks,
      selectedTrackIndex: targets.first,
      transportState: TransportState.recording,
    );
    notifyListeners();

    if (!wasPlaying) {
      await _playAudibleTracks(_state.tracks);
    }
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
      ),
    );

    final int maxSelectable = _maxSelectableTrackCount();
    if (_state.numTracksToRecord > maxSelectable) {
      _state = _state.copyWith(numTracksToRecord: maxSelectable);
      notifyListeners();
    }
  }

  List<int> _targetTrackIndexes() {
    final int selected = _state.selectedTrackIndex;
    final List<int> ordered = [
      ...List<int>.generate(_state.tracks.length - selected, (i) => i + selected),
      ...List<int>.generate(selected, (i) => i),
    ];

    final emptyTracks = ordered.where((i) => !_state.tracks[i].hasAudio).toList();
    final int desiredCount = _state.numTracksToRecord.clamp(1, emptyTracks.length);
    return emptyTracks.take(desiredCount).toList();
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
    );
    notifyListeners();

    await _playAudibleTracks(updated);
  }

  Future<void> _stopRecording({required bool continuePlayback}) async {
    if (_activeRecordingTrackIds.isEmpty) {
      _state = _state.copyWith(
        transportState: continuePlayback ? TransportState.playing : TransportState.stopped,
      );
      notifyListeners();
      return;
    }

    final Set<int> finalizedTrackIds = Set<int>.from(_activeRecordingTrackIds);
    for (final trackId in finalizedTrackIds) {
      await _audioService.stopTrackRecording(trackId);
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
    );
    notifyListeners();

    if (continuePlayback) {
      await _playAudibleTracks(updatedTracks);
    }
  }

  Future<void> _playAudibleTracks(List<Track> tracks) async {
    for (final track in tracks.where((t) => t.hasAudio && !t.isMuted)) {
      await _audioService.playTrack(track.id, loop: true);
    }
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
}
