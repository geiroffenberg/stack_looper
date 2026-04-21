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

  LooperState get state => _state;

  List<int> get availableNumTracksToRecordOptions {
    final int empty = _state.emptyTrackCount;
    if (empty <= 0) {
      return const [1];
    }
    return List<int>.generate(empty.clamp(1, AppConstants.maxTracks), (i) => i + 1);
  }

  bool get canStartRecording =>
      _state.transportState != TransportState.recording && _state.emptyTrackCount > 0;

  void setBpm(int bpm) {
    _state = _state.copyWith(bpm: bpm);
    notifyListeners();
  }

  void setRepeatCount(int repeatCount) {
    _state = _state.copyWith(repeatCount: repeatCount);
    notifyListeners();
  }

  void setNumTracksToRecord(int count) {
    final int maxSelectable = _state.emptyTrackCount.clamp(1, AppConstants.maxTracks);
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
    if (!_state.hasRecordedTracks) {
      return;
    }

    final List<Track> updated = _state.tracks
        .map(
          (track) => !track.hasAudio
              ? track
              : track.copyWith(state: TrackState.looping),
        )
        .toList(growable: false);

    _state = _state.copyWith(
      tracks: updated,
      transportState: TransportState.playing,
    );
    notifyListeners();

    for (final track in updated.where((t) => t.hasAudio && !t.isMuted)) {
      await _audioService.playTrack(track.id, loop: true);
    }
  }

  Future<void> stopAll() async {
    await _audioService.stopAll();

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
    if (!canStartRecording) {
      return;
    }

    final targets = _targetTrackIndexes();
    if (targets.isEmpty) {
      return;
    }

    _state = _state.copyWith(transportState: TransportState.recording);
    notifyListeners();

    for (final trackIndex in targets) {
      _state = _state.copyWith(selectedTrackIndex: trackIndex);
      _updateTrack(trackIndex, (track) => track.copyWith(state: TrackState.recording));

      final track = _state.tracks[trackIndex];
      await _audioService.startTrackRecording(track.id, track.barLength, _state.bpm);
      await _audioService.stopTrackRecording(track.id);

      _updateTrack(
        trackIndex,
        (t) => t.copyWith(
          hasAudio: true,
          state: _state.repeatCount <= 1 ? TrackState.playing : TrackState.looping,
        ),
      );
    }

    _state = _state.copyWith(transportState: TransportState.stopped);
    notifyListeners();
  }

  Future<void> deleteTrackAudio(int trackId) async {
    await _audioService.deleteTrack(trackId);
    _updateTrack(
      trackId,
      (track) => track.copyWith(
        hasAudio: false,
        isMuted: false,
        state: TrackState.empty,
      ),
    );

    final int maxSelectable = _state.emptyTrackCount.clamp(1, AppConstants.maxTracks);
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

  void _updateTrack(int trackId, Track Function(Track) update) {
    final List<Track> updatedTracks = List<Track>.from(_state.tracks);
    updatedTracks[trackId] = update(updatedTracks[trackId]);
    _state = _state.copyWith(tracks: updatedTracks);
    notifyListeners();
  }
}
