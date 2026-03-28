import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bimusic_app/app.dart';

void main() {
  testWidgets('BiMusicApp renders', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: BiMusicApp()));
    await tester.pumpAndSettle();
    // App launched — router redirects to /home by default
    expect(find.byType(BiMusicApp), findsOneWidget);
  });
}
