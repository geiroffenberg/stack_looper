import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../models/looper_state.dart';
import '../models/track.dart';
import '../providers/looper_provider.dart';
import '../screens/fx_screen.dart';
import '../screens/settings_screen.dart';
import '../widgets/top_menu_bar.dart';
import '../widgets/settings_bar.dart';
import '../widgets/track_card.dart';
import '../widgets/onboarding_dialog.dart';

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
  int? _lastSelectedSongTrackId;
  int? _lastLongestBarLength;

  @override
  void initState() {
    super.initState();
    _playheadController = AnimationController(vsync: this, value: 0);
    // Show onboarding card once after the first frame if not opted out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OnboardingDialog.showIfNeeded(context);
    });
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
          selectedSongTrackId: provider.selectedSongTrackId,
          selectedSongTrackBarLength:
              provider.selectedSongTrackBarLength,
          longestBarLength: provider.longestPopulatedBarLength,
        );

        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  SettingsBar(
                    bpm: state.bpm,
                    repeatCount: state.repeatCount,
                    repeatOptions: AppConstants.repeatValues,
                    onBpmChanged: provider.setBpm,
                    onRepeatChanged: provider.setRepeatCount,
                    headphoneSafetyEnabled: provider.headphoneSafetyEnabled,
                    onToggleHeadphoneSafety:
                        provider.toggleHeadphoneSafetyMode,
                    onSettingsPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
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

                        return ListView(
                          children: [
                            for (int index = 0; index < state.tracks.length; index++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Builder(
                                  builder: (context) {
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
                                    return TrackCard(
                                      track: track,
                                      isSelected: provider.selectedLoopTrackIds.contains(index),
                                      visualBarDividers: visualBarDividers,
                                      playheadProgress: trackPlayheadProgress,
                                      isArmed: isArmedTrack,
                                      armedBlinkOn: provider.armedBlinkOn,
                                      onTap: () => provider.selectTrack(index),
                                      onDelete: () => provider.deleteTrackAudio(index),
                                      onToggleDelaySend: () =>
                                          provider.toggleTrackDelaySend(index),
                                      onToggleReverbSend: () =>
                                          provider.toggleTrackReverbSend(index),
                                      onDelaySendLevelChanged: (level) =>
                                          provider.setTrackDelaySendLevel(index, level),
                                      onReverbSendLevelChanged: (level) =>
                                          provider.setTrackReverbSendLevel(index, level),
                                      onToggleMute: () => provider.toggleMute(index),
                                      onBarLengthChanged: (barLength) =>
                                          provider.setTrackBarLength(index, barLength),
                                    );
                                  },
                                ),
                              ),
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 10),
                              child: Text(
                                'SONG TRACKS',
                                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            for (int index = 0;
                                index < provider.songTracks.length;
                                index++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Builder(builder: (context) {
                                  final st = provider.songTracks[index];
                                  // Use isArmed/armedBlinkOn to show
                                  // capturing state on the waveform widget.
                                  final double songTrackProgress =
                                      !st.hasAudio
                                          ? 0.0
                                          : _trackPlayheadProgress(
                                              globalProgress:
                                                  globalPlayheadProgress,
                                              visualBarDividers:
                                                  visualBarDividers,
                                              trackBarLength: st.barLength,
                                            );
                                  return TrackCard(
                                    track: Track(
                                      id: st.id,
                                      barLength: visualBarDividers,
                                      hasAudio: st.hasAudio,
                                      isMuted: st.isMuted,
                                      waveformPeaks: st.waveformPeaks,
                                    ),
                                    fixedSlotLabel: st.label,
                                    isSongTrack: true,
                                    allowDelete: true,
                                    isSelected: provider.selectedSongTrackId ==
                                        st.id,
                                    visualBarDividers: visualBarDividers,
                                    playheadProgress: songTrackProgress,
                                    isArmed: st.isCapturing ||
                                        st.isArmedForSolo ||
                                        st.isArmedForDeselect,
                                    armedBlinkOn: (st.isCapturing ||
                                            st.isArmedForSolo ||
                                            st.isArmedForDeselect) &&
                                        provider.armedBlinkOn,
                                    armedIsRed: st.isCapturing ||
                                        st.isArmedForSolo,
                                    onDelete: () => provider.clearSongTrack(st.id),
                                    onToggleDelaySend: () {},
                                    onToggleReverbSend: () {},
                                    onDelaySendLevelChanged: (_) {},
                                    onReverbSendLevelChanged: (_) {},
                                    onToggleMute: () =>
                                        provider.toggleSongTrackMute(st.id),
                                    onBarLengthChanged: (_) {},
                                  );
                                }),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  TopMenuBar(
                    transportState: state.transportState,
                    onPlay: provider.playAll,
                    onRecord: provider.startRecordingSession,
                    onMergePressed: () async {
                      if (provider.isMergingToSongTrack) return;
                      final bool started =
                          await provider.mergeToNextSongTrack();
                      if (!started && context.mounted) {
                        final allFull = provider.songTracks
                            .every((st) => st.hasAudio);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              allFull
                                  ? 'All song tracks are full.'
                                  : 'Record some loop tracks first.',
                            ),
                          ),
                        );
                      }
                    },
                    onClearAll: provider.clearLoopTracks,
                    onFxPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const FxScreen(),
                        ),
                      );
                    },
                    canRecord: provider.canStartRecording,
                    beatFlash: provider.beatFlash,
                    recordArmed: provider.recordArmed,
                    armedBlinkOn: provider.armedBlinkOn,
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
    required int? selectedSongTrackId,
    required int? selectedSongTrackBarLength,
    required int longestBarLength,
  }) {
    // Only animate the playhead when actually playing or recording, not during count-in
    final bool isPlaying =
        state.transportState == TransportState.playing ||
        state.transportState == TransportState.recording;
    // Also animate when a song track is soloing (transport may be stopped).
    final bool songTrackSoloing = selectedSongTrackBarLength != null;
    final bool changedTransport = _lastTransportState != state.transportState;
    final bool changedTempo =
        _lastBpm != bpm || _lastVisualDividers != visualBarDividers;
    // Use the track ID (not bar length) so switching between same-length
    // tracks still resets the controller, matching the native engine which
    // always restarts the song track audio from frame 0 on selection.
    final bool changedSongTrack = _lastSelectedSongTrackId != selectedSongTrackId;
    // Detect when the native master cycle length changes (a new recording
    // finished). The native engine resets all tracks to bar 1 at this point,
    // so we must reset the animation to 0 to stay in sync.
    final bool changedMasterCycle = _lastLongestBarLength != longestBarLength;

    _lastTransportState = state.transportState;
    _lastBpm = bpm;
    _lastVisualDividers = visualBarDividers;
    _lastSelectedSongTrackId = selectedSongTrackId;
    _lastLongestBarLength = longestBarLength;

    if (!isPlaying && !songTrackSoloing) {
      if (changedTransport || changedSongTrack || _playheadController.value != 0) {
        _playheadController
          ..stop()
          ..value = 0;
      }
      return;
    }

    if (isPlaying) {
      // Reset to bar 1 whenever the transport starts or the master cycle
      // length changes (new recording completed). This keeps the playhead
      // aligned with the native engine, which also resets to bar 1 at those
      // moments.
      if (changedTransport || changedMasterCycle) {
        _playheadController.value = 0;
      }
      if (changedTransport || changedTempo || changedMasterCycle ||
          !_playheadController.isAnimating) {
        _playheadController.repeat(period: _loopPeriod(bpm, visualBarDividers));
      }
    } else {
      // Song track soloing while transport is stopped: animate at the song
      // track's own bar length.
      final Duration soloperiod = _loopPeriod(bpm, selectedSongTrackBarLength!);
      if (changedSongTrack || !_playheadController.isAnimating) {
        _playheadController
          ..value = 0
          ..repeat(period: soloperiod);
      }
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
