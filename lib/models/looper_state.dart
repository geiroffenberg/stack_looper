import 'track.dart';

enum TransportState { stopped, countIn, playing, recording }

class LooperState {
  const LooperState({
    required this.tracks,
    required this.selectedTrackIndex,
    required this.bpm,
    required this.repeatCount,
    required this.transportState,
  });

  final List<Track> tracks;
  final int selectedTrackIndex;
  final int bpm;
  final int repeatCount;
  final TransportState transportState;

  int get emptyTrackCount => tracks.where((track) => !track.hasAudio).length;
  bool get hasRecordedTracks => tracks.any((track) => track.hasAudio);

  LooperState copyWith({
    List<Track>? tracks,
    int? selectedTrackIndex,
    int? bpm,
    int? repeatCount,
    TransportState? transportState,
  }) {
    return LooperState(
      tracks: tracks ?? this.tracks,
      selectedTrackIndex: selectedTrackIndex ?? this.selectedTrackIndex,
      bpm: bpm ?? this.bpm,
      repeatCount: repeatCount ?? this.repeatCount,
      transportState: transportState ?? this.transportState,
    );
  }
}
