import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

const String _featureGuideMd = '''# Feature Guide

## Main Window
- BPM: Edit tempo (type value)
- Repeat: Number of times to repeat chained recording
- Tracks: Select how many tracks to record
- Chain: ON = record tracks in sequence; OFF = single-track record

### Track Controls
- Track Number/Value: Sets the number of bars active for that track (editable)
- DLY (Delay) Send: Toggles/controls send to Delay for the track
- REV (Reverb) Send: Toggles/controls send to Reverb for the track
- Mute: Mute/unmute the track's output

## Record / Play
- Record: Start recording armed track(s)
- Play: Start / pause playback
- Stop: Stop transport and reset playhead

## Headphones & Safety
- No Headphones: Mute other tracks and audible metronome while recording (visual metronome remains)
- Metronome: Toggle audible metronome on/off

## Reset (Trash)
- Reset All (Trash): Clears audio from all tracks, returning them to empty

## Quick Actions
- Mixer / FX: Open per-track mixer and effects chain
- Settings: Open app settings and appearance

---

## Mixer & FX

### Sends & FX
- Send (DLY / REV): Routes a portion of the track signal to Delay or Reverb
- Delay: Time-based echo effect; use send level to control how much is sent
- Reverb: Space/ambience effect; send level controls wet amount

### Track FX
- Add Effect: Insert effect into the track's effect chain
- Bypass: Temporarily disable the effect
- Parameters: Knobs/sliders to tune the effect
- Reorder: Move effects within the chain

### Master FX
- Highpass: Removes low frequencies below the cutoff frequency to reduce rumble and stage noise.
- Lowpass: Removes high frequencies above the cutoff to tame excessive brightness or hiss.
- Three-band EQ: Independent low, mid, and high bands for tone shaping (boost or cut each band).
- Compressor: Reduces dynamic range by attenuating peaks and increasing perceived sustain.
- Saturation: Adds harmonic coloration and mild distortion to warm or thicken the sound.
- Limiter: Hard ceiling that prevents clipping by capping peaks at a set threshold.

## Mixer & Master Volume
- Track Fader: Adjusts track gain (louder / quieter)
- Master Fader: Adjusts overall output level

(Short, symbol-led reference — tap `Feature Guide` anytime in Settings.)
''';

class FeatureGuideDialog {
  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Feature Guide'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: MarkdownBody(data: _featureGuideMd),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
