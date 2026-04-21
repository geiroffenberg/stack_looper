enum TrackState { empty, recording, playing, looping }

class Track {
  const Track({
    required this.id,
    required this.barLength,
    this.hasAudio = false,
    this.isMuted = false,
    this.state = TrackState.empty,
  });

  final int id;
  final int barLength;
  final bool hasAudio;
  final bool isMuted;
  final TrackState state;

  bool get canMute => hasAudio;

  Track copyWith({
    int? id,
    int? barLength,
    bool? hasAudio,
    bool? isMuted,
    TrackState? state,
  }) {
    return Track(
      id: id ?? this.id,
      barLength: barLength ?? this.barLength,
      hasAudio: hasAudio ?? this.hasAudio,
      isMuted: isMuted ?? this.isMuted,
      state: state ?? this.state,
    );
  }
}
