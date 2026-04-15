import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/models/album.dart';
import 'package:bimusic_app/models/artist.dart';
import 'package:bimusic_app/models/auth_tokens.dart';
import 'package:bimusic_app/models/user.dart';
import 'package:bimusic_app/providers/auth_provider.dart';
import 'package:bimusic_app/providers/library_provider.dart';
import 'package:bimusic_app/services/auth_service.dart';
import 'package:bimusic_app/ui/screens/home_screen.dart';

class _MockAuthService extends Mock implements AuthService {}

class _StubLibraryNotifier extends LibraryNotifier {
  final List<Artist> _artists;
  _StubLibraryNotifier(this._artists);

  @override
  Future<List<Artist>> build() async => _artists;
}

class _StubAuthNotifier extends Notifier<AuthState> implements AuthNotifier {
  final AuthState _state;
  _StubAuthNotifier(this._state);

  @override
  Future<void> get initialized async {}

  @override
  AuthState build() => _state;

  @override
  Future<void> login(String username, String password) async {}

  @override
  Future<void> logout() async {}
}

const _testUser = User(
  userId: 'user-1',
  username: 'testuser',
  isAdmin: false,
);

const _testTokens = AuthTokens(
  accessToken: 'access_token',
  refreshToken: 'refresh_token',
  user: _testUser,
);

const _testArtists = <Artist>[
  Artist(
    id: 1,
    name: 'Alpha Artist',
    overview: 'Overview',
    imageUrl: 'http://example.com/1.jpg',
    albumCount: 2,
  ),
  Artist(
    id: 2,
    name: 'Beta Artist',
    overview: 'Overview 2',
    imageUrl: 'http://example.com/2.jpg',
    albumCount: 1,
  ),
];

const _testAlbums = <Album>[
  Album(
    id: 10,
    title: 'First Album',
    artistId: 1,
    artistName: 'Alpha Artist',
    imageUrl: 'http://example.com/album.jpg',
    releaseDate: '2020-01-01',
    genres: ['Rock'],
    trackCount: 5,
    duration: 1200000,
  ),
];

void main() {
  late _MockAuthService mockAuthService;

  setUp(() {
    mockAuthService = _MockAuthService();
    when(() => mockAuthService.accessToken).thenReturn('test_token');
  });

  Widget buildSubject({
    List<Artist> artists = _testArtists,
    AuthState? authState,
  }) {
    final state = authState ?? const AuthStateAuthenticated(_testTokens);
    return ProviderScope(
      overrides: [
        authServiceProvider.overrideWith((_) => mockAuthService),
        authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(state),
        ),
        libraryProvider.overrideWith(
          () => _StubLibraryNotifier(artists),
        ),
        artistAlbumsProvider(1).overrideWith(
          (_) async => _testAlbums,
        ),
        artistAlbumsProvider(2).overrideWith(
          (_) async => <Album>[],
        ),
      ],
      child: const MaterialApp(home: HomeScreen()),
    );
  }

  testWidgets('renders Home title', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('shows welcome greeting with username', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();
    expect(find.text('Welcome back, testuser!'), findsOneWidget);
  });

  testWidgets('shows quick-nav shortcuts', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
  });

  testWidgets('shows artist names after loading', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();
    expect(find.text('Alpha Artist'), findsOneWidget);
    expect(find.text('Beta Artist'), findsOneWidget);
  });

  testWidgets('shows loading indicator while fetching artists', (tester) async {
    await tester.pumpWidget(buildSubject());
    // Before pump() resolves futures, loading indicator should show
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows "No artists" message when library is empty', (tester) async {
    await tester.pumpWidget(buildSubject(artists: []));
    await tester.pump();
    expect(find.text('No artists in your library yet.'), findsOneWidget);
  });

  testWidgets('shows generic greeting when unauthenticated', (tester) async {
    await tester.pumpWidget(
      buildSubject(authState: const AuthStateUnauthenticated()),
    );
    await tester.pump();
    expect(find.text('Welcome back!'), findsOneWidget);
  });
}
