import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../models/looper_state.dart';
import '../providers/looper_provider.dart';
import '../widgets/top_menu_bar.dart';
import '../widgets/track_card.dart';

class LooperScreen extends StatefulWidget {
  const LooperScreen({super.key});

  @override
  State<LooperScreen> createState() => _LooperScreenState();
}

class _LooperScreenState extends State<LooperScreen>
    with SingleTickerProviderStateMixin {
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
                    bpm: state.bpm,
                    repeatCount: state.repeatCount,
                    numTracksToRecord: state.numTracksToRecord,
                    repeatOptions: AppConstants.repeatValues,
                    numTrackOptions: provider.availableNumTracksToRecordOptions,
                    onPlay: provider.playAll,
                    onRecord: provider.startRecordingSession,
                    onBpmChanged: provider.setBpm,
                    onRepeatChanged: provider.setRepeatCount,
                    onNumTracksChanged: provider.setNumTracksToRecord,
                    canRecord: provider.canStartRecording,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _playheadController,
                      builder: (context, _) {
                        final double playheadProgress =
                            state.transportState == TransportState.stopped
                                ? 0
                                : _playheadController.value;

                        return ListView.builder(
                          itemCount: state.tracks.length,
                          itemBuilder: (context, index) {
                            final track = state.tracks[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: TrackCard(
                                track: track,
                                isSelected: state.selectedTrackIndex == index,
                                visualBarDividers: visualBarDividers,
                                playheadProgress: playheadProgress,
                                onSelect: () => provider.selectTrack(index),
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
    final bool isPlaying = state.transportState != TransportState.stopped;
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

    if (changedTransport || changedTempo || !_playheadController.isAnimating) {
      _playheadController.repeat(period: _loopPeriod(bpm, visualBarDividers));
    }
  }

  Duration _loopPeriod(int bpm, int barCount) {
    final double beatsPerSecond = bpm / 60;
    final double beatsPerLoop = barCount * 4;
    final int milliseconds = (beatsPerLoop / beatsPerSecond * 1000).round();
    return Duration(milliseconds: milliseconds.clamp(250, 120000).toInt());
  }
}
