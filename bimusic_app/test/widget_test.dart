import 'package:flutter_test/flutter_test.dart';
import 'package:bimusic_app/main.dart';

void main() {
  testWidgets('BiMusicApp renders', (WidgetTester tester) async {
    await tester.pumpWidget(const BiMusicApp());
    expect(find.text('BiMusic'), findsOneWidget);
  });
}
