import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/models/artist.dart';
import 'package:bimusic_app/providers/library_provider.dart';
import 'package:bimusic_app/services/auth_service.dart';
import 'package:bimusic_app/ui/screens/library_screen.dart';

class _MockAuthService extends Mock implements AuthService {}

class _StubLibraryNotifier extends LibraryNotifier {
  final List<Artist> _artists;
  _StubLibraryNotifier(this._artists);

  @override
  Future<List<Artist>> build() async => _artists;
}

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

void main() {
  late _MockAuthService mockAuthService;

  setUp(() {
    mockAuthService = _MockAuthService();
    when(() => mockAuthService.accessToken).thenReturn('test_token');
  });

  Widget buildSubject(List<Artist> artists) => ProviderScope(
        overrides: [
          authServiceProvider.overrideWith((_) => mockAuthService),
          libraryProvider.overrideWith(() => _StubLibraryNotifier(artists)),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      );

  testWidgets('renders Library title', (tester) async {
    await tester.pumpWidget(buildSubject(_testArtists));
    await tester.pump();
    expect(find.text('Library'), findsOneWidget);
  });

  testWidgets('renders artist names', (tester) async {
    await tester.pumpWidget(buildSubject(_testArtists));
    await tester.pump();
    expect(find.text('Alpha Artist'), findsOneWidget);
    expect(find.text('Beta Artist'), findsOneWidget);
  });

  testWidgets('shows "No artists in library" when list is empty', (tester) async {
    await tester.pumpWidget(buildSubject([]));
    await tester.pump();
    expect(find.text('No artists in library'), findsOneWidget);
  });

  testWidgets('shows loading indicator while fetching', (tester) async {
    await tester.pumpWidget(buildSubject(_testArtists));
    // Before pump() resolves futures, show loading state
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
