import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'constants/app_theme.dart';
import 'providers/looper_provider.dart';
import 'screens/looper_screen.dart';
import 'services/audio_service.dart';
import 'services/native_audio_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Chunk 9: do NOT block main() on native engine startup. Opening the
  // duplex Oboe stream can take a few hundred ms (mic permission, exclusive
  // mode negotiation), and awaiting it here means the user sees nothing
  // but the launch logo until it finishes. Instead, create the service and
  // kick off initialize() asynchronously — the UI can render immediately.
  final audioService = NativeAudioService();
  _bootAudio(audioService);

  runApp(MyApp(audioService: audioService));
}

/// Requests mic permission, then starts the native engine. Runs async off
/// the main() thread so the UI can render immediately. Logs failures to
/// console instead of throwing — a missing mic permission just means
/// recording will produce silence, not that the app is broken.
Future<void> _bootAudio(NativeAudioService service) async {
  try {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      debugPrint('[main] mic permission not granted: $status');
      // Still start the engine — metronome/playback work without mic.
    }
    await service.initialize();
    debugPrint('[main] NativeAudioService initialized');
  } catch (err, st) {
    debugPrint('[main] NativeAudioService init failed: $err\n$st');
  }
}

class MyApp extends StatelessWidget {
  final AudioService audioService;

  const MyApp({super.key, required this.audioService});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LooperProvider(audioService: audioService),
      child: MaterialApp(
        title: 'Stack Looper',
        theme: AppTheme.darkMinimal,
        home: const LooperScreen(),
      ),
    );
  }
}
