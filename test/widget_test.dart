import 'package:flutter_test/flutter_test.dart';

import 'package:stack_looper/main.dart';

void main() {
  testWidgets('renders looper scaffold with menu and tracks', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Stack Looper'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
    expect(find.text('Repeat'), findsOneWidget);
    expect(find.text('Tracks'), findsOneWidget);
    expect(find.text('Track 1'), findsOneWidget);
    expect(find.text('Track 8'), findsOneWidget);
  });
}
