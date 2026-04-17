import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/providers/backend_url_provider.dart';
import 'package:bimusic_app/ui/screens/backend_setup_screen.dart';

// ---------------------------------------------------------------------------
// Stub — captures setUrl calls and controls success/failure
// ---------------------------------------------------------------------------

class _StubBackendUrlNotifier extends BackendUrlNotifier {
  _StubBackendUrlNotifier({this.throwOnSet});

  final Object? throwOnSet;
  String? lastSetUrl;

  @override
  Future<String?> build() async => null;

  @override
  Future<void> setUrl(String raw) async {
    lastSetUrl = raw;
    if (throwOnSet != null) throw throwOnSet!;
    state = AsyncData(raw);
  }

  @override
  Future<void> clearUrl() async {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('BackendSetupScreen', () {
    testWidgets('renders Server URL field and Connect button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendUrlProvider.overrideWith(() => _StubBackendUrlNotifier()),
          ],
          child: const MaterialApp(home: BackendSetupScreen()),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('shows error when URL is empty', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendUrlProvider.overrideWith(() => _StubBackendUrlNotifier()),
          ],
          child: const MaterialApp(home: BackendSetupScreen()),
        ),
      );

      // Clear the default 'http://' text so the field is blank.
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      await tester.tap(find.text('Connect'));
      await tester.pump();

      expect(find.text('Please enter the backend URL.'), findsOneWidget);
    });

    testWidgets('shows error message returned by notifier on failure',
        (tester) async {
      final stub = _StubBackendUrlNotifier(
        throwOnSet: 'Could not reach server: connection refused',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendUrlProvider.overrideWith(() => stub),
          ],
          child: const MaterialApp(home: BackendSetupScreen()),
        ),
      );

      await tester.enterText(find.byType(TextField), 'http://bad-host:3000');
      await tester.pump();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not reach server: connection refused'),
        findsOneWidget,
      );
    });

    testWidgets('calls notifier.setUrl with entered text on success',
        (tester) async {
      final stub = _StubBackendUrlNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendUrlProvider.overrideWith(() => stub),
          ],
          child: const MaterialApp(home: BackendSetupScreen()),
        ),
      );

      await tester.enterText(find.byType(TextField), 'http://192.168.1.5:3000');
      await tester.pump();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(stub.lastSetUrl, 'http://192.168.1.5:3000');
    });

    testWidgets('shows initialError when provided', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendUrlProvider.overrideWith(() => _StubBackendUrlNotifier()),
          ],
          child: const MaterialApp(
            home: BackendSetupScreen(initialError: 'Storage read failed'),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Storage read failed'), findsOneWidget);
    });
  });
}
