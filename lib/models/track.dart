enum TrackState { empty, armed, recording, playing, looping }

class Track {
  const Track({
    required this.id,
    required this.barLength,
    this.hasAudio = false,
    this.isMuted = false,
    this.delaySendEnabled = false,
    this.delaySendLevel = 1.0,
    this.reverbSendEnabled = false,
    this.reverbSendLevel = 1.0,
    this.state = TrackState.empty,
    this.waveformPeaks = const <double>[],
  });

  final int id;
  final int barLength;
  final bool hasAudio;
  final bool isMuted;
  final bool delaySendEnabled;
  final double delaySendLevel;
  final bool reverbSendEnabled;
  final double reverbSendLevel;
  final TrackState state;
  final List<double> waveformPeaks;

  bool get canMute => hasAudio;

  Track copyWith({
    int? id,
    int? barLength,
    bool? hasAudio,
    bool? isMuted,
    bool? delaySendEnabled,
    double? delaySendLevel,
    bool? reverbSendEnabled,
    double? reverbSendLevel,
    TrackState? state,
    List<double>? waveformPeaks,
  }) {
    return Track(
      id: id ?? this.id,
      barLength: barLength ?? this.barLength,
      hasAudio: hasAudio ?? this.hasAudio,
      isMuted: isMuted ?? this.isMuted,
      delaySendEnabled: delaySendEnabled ?? this.delaySendEnabled,
      delaySendLevel: delaySendLevel ?? this.delaySendLevel,
      reverbSendEnabled: reverbSendEnabled ?? this.reverbSendEnabled,
      reverbSendLevel: reverbSendLevel ?? this.reverbSendLevel,
      state: state ?? this.state,
      waveformPeaks: waveformPeaks ?? this.waveformPeaks,
    );
  }
}
