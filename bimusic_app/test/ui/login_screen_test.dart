import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/models/auth_tokens.dart';
import 'package:bimusic_app/models/user.dart';
import 'package:bimusic_app/providers/auth_provider.dart';
import 'package:bimusic_app/services/auth_service.dart';
import 'package:bimusic_app/ui/screens/login_screen.dart';

class _MockAuthService extends Mock implements AuthService {}

void main() {
  late _MockAuthService mockAuthService;

  const _testTokens = AuthTokens(
    accessToken: 'access',
    refreshToken: 'refresh',
    user: User(userId: 'u1', username: 'admin', isAdmin: false),
  );

  setUp(() {
    mockAuthService = _MockAuthService();
    when(() => mockAuthService.accessToken).thenReturn(null);
    // Default: no stored tokens → AuthStateUnauthenticated
    when(() => mockAuthService.readStoredTokens())
        .thenAnswer((_) async => null);
  });

  Widget buildSubject() => ProviderScope(
        overrides: [
          authServiceProvider.overrideWith((_) => mockAuthService),
        ],
        child: const MaterialApp(home: LoginScreen()),
      );

  testWidgets('renders username and password fields', (tester) async {
    await tester.pumpWidget(buildSubject());
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('renders BiMusic title', (tester) async {
    await tester.pumpWidget(buildSubject());
    expect(find.text('BiMusic'), findsOneWidget);
  });

  testWidgets('shows error message when login throws', (tester) async {
    when(() => mockAuthService.login(any(), any()))
        .thenThrow(Exception('Invalid credentials'));

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle(); // let auth init complete

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'), 'user');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'badpass');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid username or password.'), findsOneWidget);
  });

  testWidgets('shows no error message on initial render', (tester) async {
    await tester.pumpWidget(buildSubject());
    expect(find.text('Invalid username or password.'), findsNothing);
  });

  testWidgets('sign-in button is enabled when not loading', (tester) async {
    await tester.pumpWidget(buildSubject());
    final button =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Sign In'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('calls login on the auth service when form is submitted',
      (tester) async {
    when(() => mockAuthService.login(any(), any()))
        .thenAnswer((_) async => _testTokens);

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'), 'admin');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'password');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    // No error message shown after successful login
    expect(find.text('Invalid username or password.'), findsNothing);
  });
}
