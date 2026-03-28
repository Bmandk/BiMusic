import 'package:bimusic_app/models/album.dart';
import 'package:bimusic_app/models/track.dart';
import 'package:bimusic_app/providers/library_provider.dart';
import 'package:bimusic_app/services/auth_service.dart';
import 'package:bimusic_app/ui/screens/album_detail_screen.dart';
import 'package:bimusic_app/ui/widgets/track_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthService extends Mock implements AuthService {}

const _testAlbum = Album(
  id: 1,
  title: 'Test Album',
  artistId: 10,
  artistName: 'Test Artist',
  imageUrl: 'http://example.com/album.jpg',
  releaseDate: '2020-06-15',
  genres: ['Rock'],
  trackCount: 2,
  duration: 300000,
);

final _testTracks = [
  const Track(
    id: 1,
    title: 'First Track',
    trackNumber: '1',
    duration: 180000,
    albumId: 1,
    artistId: 10,
    hasFile: true,
    streamUrl: 'http://example.com/stream/1',
  ),
  const Track(
    id: 2,
    title: 'Second Track',
    trackNumber: '2',
    duration: 120000,
    albumId: 1,
    artistId: 10,
    hasFile: false,
    streamUrl: 'http://example.com/stream/2',
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
          albumProvider(1).overrideWith((_) async => _testAlbum),
          albumTracksProvider(1).overrideWith((_) async => _testTracks),
        ],
        child: const MaterialApp(
          home: AlbumDetailScreen(id: '1'),
        ),
      );

  testWidgets('renders album title and artist name', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump(); // resolve futures

    expect(find.text('Test Artist'), findsOneWidget);
    expect(find.text('2020'), findsOneWidget);
  });

  testWidgets('renders track list from provider state', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.byType(TrackTile), findsNWidgets(2));
    expect(find.text('First Track'), findsOneWidget);
    expect(find.text('Second Track'), findsOneWidget);
  });

  testWidgets('shows loading indicator while tracks are loading',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    // Before pump — futures not yet resolved
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });
}
