import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../models/looper_state.dart';
import '../providers/looper_provider.dart';
import '../widgets/top_menu_bar.dart';
import '../widgets/track_card.dart';

class LooperScreen extends StatelessWidget {
  const LooperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LooperProvider>(
      builder: (context, provider, _) {
        final state = provider.state;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Stack Looper'),
            centerTitle: false,
          ),
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
                    bpmOptions: AppConstants.bpmValues,
                    repeatOptions: AppConstants.repeatValues,
                    numTrackOptions: provider.availableNumTracksToRecordOptions,
                    onPlay: provider.playAll,
                    onStop: provider.stopAll,
                    onRecord: provider.startRecordingSession,
                    onBpmChanged: provider.setBpm,
                    onRepeatChanged: provider.setRepeatCount,
                    onNumTracksChanged: provider.setNumTracksToRecord,
                    canPlay: state.hasRecordedTracks,
                    canStop: state.transportState != TransportState.stopped,
                    canRecord: provider.canStartRecording,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: state.tracks.length,
                      itemBuilder: (context, index) {
                        final track = state.tracks[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TrackCard(
                            track: track,
                            isSelected: state.selectedTrackIndex == index,
                            onSelect: () => provider.selectTrack(index),
                            onDelete: () => provider.deleteTrackAudio(index),
                            onToggleMute: () => provider.toggleMute(index),
                            onBarLengthChanged: (barLength) =>
                                provider.setTrackBarLength(index, barLength),
                          ),
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
}
