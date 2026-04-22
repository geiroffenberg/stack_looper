import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_looper/constants/app_constants.dart';
import 'package:stack_looper/main.dart';
import 'package:stack_looper/services/audio_service.dart';
import 'package:stack_looper/widgets/track_card.dart';

void main() {
  testWidgets('renders minimalist looper layout', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MyApp(audioService: AudioServiceStub()));

    expect(find.text('Stack Looper'), findsNothing);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fiber_manual_record_rounded), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(TrackCard), findsNWidgets(AppConstants.maxTracks));
  });
}
