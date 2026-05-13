import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingDialog extends StatefulWidget {
  const OnboardingDialog({super.key});

  static const String _kDontShowKey = 'dont_show_onboarding';

  static Future<void> showIfNeeded(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final hide = prefs.getBool(_kDontShowKey) ?? false;
    if (hide) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const OnboardingDialog(),
    );
  }

  @override
  State<OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<OnboardingDialog> {
  bool _dontShowAgain = false;

  Future<void> _savePreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingDialog._kDontShowKey, _dontShowAgain);
  }

  @override
  Widget build(BuildContext context) {


    return AlertDialog(
      title: const Text('Quick Tips'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: const [
                Icon(Icons.headphones),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Headphones recommended: use headphones or a line-in instrument to avoid the phone mic re-recording the speakers.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.headset_off_rounded),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      const TextSpan(
                        text:
                            'If you want to record without headphones, tap ',
                      ),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Icon(Icons.headset_off_rounded, size: 18),
                      ),
                      const TextSpan(
                        text:
                            ' "No headphones" — this will silence other tracks and the metronome while recording. The flashing recording light still shows timing.',
                      ),
                    ]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.repeat),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Workflow: this app CAN be used as a normal track-by-track looper, but the intended workflow is to pre-set each track length and record tracks in a chained session. Toggle the Chain button to enable/disable chained multi-track recording (default ON). Example: set track 1 to 1 bar, track 2 to 2 bars — record the 1-bar beat, then immediately record chords on track 2. Use the Repeat button to set how many times a track repeats before recording moves to the next track.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Don't show again"),
              value: _dontShowAgain,
              onChanged: (v) => setState(() => _dontShowAgain = v ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await _savePreference();
            Navigator.of(context).pop();
          },
          child: const Text('Got it'),
        ),
        // Only keep the acknowledgement action; the checkbox persists.
      ],
    );
  }
}
