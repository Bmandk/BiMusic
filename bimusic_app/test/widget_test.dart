import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bimusic_app/app.dart';
import 'package:bimusic_app/providers/backend_url_provider.dart';
import 'package:bimusic_app/ui/screens/backend_setup_screen.dart';

class _StubBackendUrlNotifier extends BackendUrlNotifier {
  @override
  Future<String?> build() async => null;

  @override
  Future<void> setUrl(String raw) async {}

  @override
  Future<void> clearUrl() async {}
}

class _ErrorBackendUrlNotifier extends BackendUrlNotifier {
  @override
  Future<String?> build() async => throw Exception('storage failed');

  @override
  Future<void> setUrl(String raw) async {}

  @override
  Future<void> clearUrl() async {}
}

void main() {
  testWidgets('BiMusicApp renders BackendSetupScreen when URL is null',
      (WidgetTester tester) async {
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
    expect(find.byType(BackendSetupScreen), findsOneWidget);
  });

  testWidgets(
      'BiMusicApp renders BackendSetupScreen with error when provider fails',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendUrlProvider.overrideWith(() => _ErrorBackendUrlNotifier()),
        ],
        child: const BiMusicApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackendSetupScreen), findsOneWidget);
    expect(find.textContaining('storage failed'), findsOneWidget);
  });
}
