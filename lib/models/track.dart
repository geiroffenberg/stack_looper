enum TrackState { empty, armed, recording, playing, looping }

/// One of the three fixed render-down slots (A / B / C).
/// Song tracks capture the fully-processed master output for one full loop.
class SongTrack {
  const SongTrack({
    required this.id,
    required this.label,
    this.hasAudio = false,
    this.isMuted = true,
    this.isCapturing = false,
    this.waveformPeaks = const <double>[],
    this.barLength = 1,
  });

  /// Native-side index (0, 1, 2) is `id - 100`.
  final int id;
  final String label;
  final bool hasAudio;
  final bool isMuted;
  final bool isCapturing;
  final List<double> waveformPeaks;
  final int barLength;

  SongTrack copyWith({
    int? id,
    String? label,
    bool? hasAudio,
    bool? isMuted,
    bool? isCapturing,
    List<double>? waveformPeaks,
    int? barLength,
  }) {
    return SongTrack(
      id: id ?? this.id,
      label: label ?? this.label,
      hasAudio: hasAudio ?? this.hasAudio,
      isMuted: isMuted ?? this.isMuted,
      isCapturing: isCapturing ?? this.isCapturing,
      waveformPeaks: waveformPeaks ?? this.waveformPeaks,
      barLength: barLength ?? this.barLength,
    );
  }
}

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
