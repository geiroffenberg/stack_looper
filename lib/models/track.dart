enum TrackState { empty, armed, recording, playing, looping }

class Track {
  const Track({
    required this.id,
    required this.barLength,
    this.hasAudio = false,
    this.isMuted = false,
    this.delaySendEnabled = true,
    this.reverbSendEnabled = true,
    this.state = TrackState.empty,
    this.waveformPeaks = const <double>[],
  });

  final int id;
  final int barLength;
  final bool hasAudio;
  final bool isMuted;
  final bool delaySendEnabled;
  final bool reverbSendEnabled;
  final TrackState state;
  final List<double> waveformPeaks;

  bool get canMute => hasAudio;

  Track copyWith({
    int? id,
    int? barLength,
    bool? hasAudio,
    bool? isMuted,
    bool? delaySendEnabled,
    bool? reverbSendEnabled,
    TrackState? state,
    List<double>? waveformPeaks,
  }) {
    return Track(
      id: id ?? this.id,
      barLength: barLength ?? this.barLength,
      hasAudio: hasAudio ?? this.hasAudio,
      isMuted: isMuted ?? this.isMuted,
      delaySendEnabled: delaySendEnabled ?? this.delaySendEnabled,
      reverbSendEnabled: reverbSendEnabled ?? this.reverbSendEnabled,
      state: state ?? this.state,
      waveformPeaks: waveformPeaks ?? this.waveformPeaks,
    );
  }
}
