import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bimusic_app/app.dart';
import 'package:bimusic_app/providers/backend_url_provider.dart';

class _StubBackendUrlNotifier extends BackendUrlNotifier {
  @override
  Future<String?> build() async => null;

  @override
  Future<void> setUrl(String raw) async {}

  @override
  Future<void> clearUrl() async {}
}

void main() {
  testWidgets('BiMusicApp renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendUrlProvider.overrideWith(() => _StubBackendUrlNotifier()),
        ],
        child: const BiMusicApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BiMusicApp), findsOneWidget);
  });
}
