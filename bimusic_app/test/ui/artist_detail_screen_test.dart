import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/models/album.dart';
import 'package:bimusic_app/models/artist.dart';
import 'package:bimusic_app/providers/library_provider.dart';
import 'package:bimusic_app/services/auth_service.dart';
import 'package:bimusic_app/ui/screens/artist_detail_screen.dart';

class _MockAuthService extends Mock implements AuthService {}

const _testArtist = Artist(
  id: 1,
  name: 'Test Artist',
  overview: 'A test artist overview',
  imageUrl: 'http://example.com/artist.jpg',
  albumCount: 1,
);

const _testAlbums = [
  Album(
    id: 10,
    title: 'First Album',
    artistId: 1,
    artistName: 'Test Artist',
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

  Widget buildSubject() => ProviderScope(
        overrides: [
          authServiceProvider.overrideWith((_) => mockAuthService),
          artistProvider(1).overrideWith((_) async => _testArtist),
          artistAlbumsProvider(1).overrideWith((_) async => _testAlbums),
        ],
        child: const MaterialApp(
          home: ArtistDetailScreen(id: '1'),
        ),
      );

  testWidgets('renders artist name', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();
    expect(find.text('Test Artist'), findsOneWidget);
  });

  testWidgets('renders album in the list', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();
    expect(find.text('First Album'), findsOneWidget);
  });

  testWidgets('shows loading indicator while fetching', (tester) async {
    await tester.pumpWidget(buildSubject());
    // Before pump() resolves futures, loading indicator should show
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
