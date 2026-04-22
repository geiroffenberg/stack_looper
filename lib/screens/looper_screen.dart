import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../models/looper_state.dart';
import '../providers/looper_provider.dart';
import '../widgets/top_menu_bar.dart';
import '../widgets/settings_bar.dart';
import '../widgets/track_card.dart';

class LooperScreen extends StatefulWidget {
  const LooperScreen({super.key});

  @override
  State<LooperScreen> createState() => _LooperScreenState();
}

class _LooperScreenState extends State<LooperScreen>
    with SingleTickerProviderStateMixin {
  static const int _beatsPerBar = 4; // Number of beats per bar (4/4 time).
  // Guardrails for visual animation speed:
  // - Min keeps very high BPM from becoming unreadably fast.
  // - Max keeps very low BPM / long loops from becoming unresponsive.
  static const int _minLoopDurationMs = 250;
  static const int _maxLoopDurationMs = 120000;

  late final AnimationController _playheadController;
  TransportState? _lastTransportState;
  int? _lastBpm;
  int? _lastVisualDividers;

  @override
  void initState() {
    super.initState();
    _playheadController = AnimationController(vsync: this, value: 0);
  }

  @override
  void dispose() {
    _playheadController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LooperProvider>(
      builder: (context, provider, _) {
        final state = provider.state;
        final visualBarDividers = provider.visualBarDividers;
        _syncPlayhead(
          state: state,
          bpm: state.bpm,
          visualBarDividers: visualBarDividers,
        );

        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TopMenuBar(
                    transportState: state.transportState,
                    onPlay: provider.playAll,
                    onRecord: provider.startRecordingSession,
                    canRecord: provider.canStartRecording,
                    beatFlash: provider.beatFlash,
                    recordArmed: provider.recordArmed,
                    armedBlinkOn: provider.armedBlinkOn,
                    onSettingsPressed: () {
                      // TODO: Implement settings menu
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _playheadController,
                      builder: (context, _) {
                        final double globalPlayheadProgress =
                            (state.transportState == TransportState.playing ||
                                    state.transportState ==
                                        TransportState.recording)
                                ? _playheadController.value
                                : 0;

                        return ListView.builder(
                          itemCount: state.tracks.length,
                          itemBuilder: (context, index) {
                            final track = state.tracks[index];
                            final bool isArmedTrack =
                                provider.armedTrackId != null &&
                                provider.armedTrackId == track.id;
                            final double trackPlayheadProgress =
                                _trackPlayheadProgress(
                              globalProgress: globalPlayheadProgress,
                              visualBarDividers: visualBarDividers,
                              trackBarLength: track.barLength,
                            );
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: TrackCard(
                                track: track,
                                isSelected: !track.hasAudio && state.selectedTrackIndex == index,
                                visualBarDividers: visualBarDividers,
                                playheadProgress: isArmedTrack ? 0 : trackPlayheadProgress,
                                isArmed: isArmedTrack,
                                armedBlinkOn: provider.armedBlinkOn,
                                onDelete: () => provider.deleteTrackAudio(index),
                                onToggleMute: () => provider.toggleMute(index),
                                onBarLengthChanged: (barLength) =>
                                    provider.setTrackBarLength(index, barLength),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  SettingsBar(
                    bpm: state.bpm,
                    repeatCount: state.repeatCount,
                    numTracksToRecord: state.numTracksToRecord,
                    repeatOptions: AppConstants.repeatValues,
                    numTrackOptions: provider.availableNumTracksToRecordOptions,
                    onBpmChanged: provider.setBpm,
                    onRepeatChanged: provider.setRepeatCount,
                    onNumTracksChanged: provider.setNumTracksToRecord,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _syncPlayhead({
    required LooperState state,
    required int bpm,
    required int visualBarDividers,
  }) {
    // Only animate the playhead when actually playing or recording, not during count-in
    final bool isPlaying = state.transportState == TransportState.playing ||
        state.transportState == TransportState.recording;
    final bool changedTransport = _lastTransportState != state.transportState;
    final bool changedTempo = _lastBpm != bpm || _lastVisualDividers != visualBarDividers;

    _lastTransportState = state.transportState;
    _lastBpm = bpm;
    _lastVisualDividers = visualBarDividers;

    if (!isPlaying) {
      if (changedTransport || _playheadController.value != 0) {
        _playheadController
          ..stop()
          ..value = 0;
      }
      return;
    }

    // Entering recording (or any new transport phase) should start the
    // playhead from 0 so armed tracks don't paint mid-cycle.
    if (changedTransport) {
      _playheadController.value = 0;
    }

    if (changedTransport || changedTempo || !_playheadController.isAnimating) {
      _playheadController.repeat(period: _loopPeriod(bpm, visualBarDividers));
    }
  }

  Duration _loopPeriod(int bpm, int barCount) {
    final int milliseconds = ((barCount * _beatsPerBar * 60000) / bpm).round();
    return Duration(
      milliseconds: milliseconds
          .clamp(_minLoopDurationMs, _maxLoopDurationMs)
          .toInt(),
    );
  }

  // Converts one global transport phase into a track-local playhead position.
  // A 1-bar track inside a 4-bar session resets 4x while a 4-bar track resets once.
  double _trackPlayheadProgress({
    required double globalProgress,
    required int visualBarDividers,
    required int trackBarLength,
  }) {
    final int safeDividers = visualBarDividers <= 0 ? 1 : visualBarDividers;
    final int safeTrackBars = trackBarLength <= 0 ? 1 : trackBarLength;
    final double globalBars = globalProgress.clamp(0.0, 1.0) * safeDividers;
    final double localBars = globalBars % safeTrackBars;
    return (localBars / safeDividers).clamp(0.0, 1.0);
  }
}
