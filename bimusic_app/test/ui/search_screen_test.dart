import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/models/album.dart';
import 'package:bimusic_app/models/artist.dart';
import 'package:bimusic_app/models/lidarr_search_results.dart';
import 'package:bimusic_app/models/music_request.dart';
import 'package:bimusic_app/models/search_results.dart';
import 'package:bimusic_app/providers/requests_provider.dart';
import 'package:bimusic_app/providers/search_provider.dart';
import 'package:bimusic_app/services/search_service.dart';
import 'package:bimusic_app/ui/screens/search_screen.dart';

class _MockSearchService extends Mock implements SearchService {}

/// A stub that supports pre-seeding state for widget tests.
class _StubSearchNotifier extends SearchNotifier {
  _StubSearchNotifier(super.searchService, [SearchState? initialState]) {
    if (initialState != null) state = initialState;
  }
}

class _StubRequestsNotifier extends RequestsNotifier {
  _StubRequestsNotifier(this._requests);
  final List<MusicRequest> _requests;

  @override
  Future<List<MusicRequest>> build() async => _requests;
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

const _testArtist = Artist(
  id: 1,
  name: 'Test Artist',
  imageUrl: 'http://example.com/artist.jpg',
  albumCount: 3,
);

const _testAlbum = Album(
  id: 10,
  title: 'Test Album',
  artistId: 1,
  artistName: 'Test Artist',
  imageUrl: 'http://example.com/album.jpg',
  trackCount: 12,
  duration: 2400,
  genres: [],
  releaseDate: '2020-06-15',
);

const _lidarrArtist = LidarrArtistResult(
  id: 42,
  artistName: 'Lidarr Artist',
  foreignArtistId: 'mbid-42',
  images: [],
);

const _lidarrAlbum = LidarrAlbumResult(
  id: 20,
  title: 'Lidarr Album',
  artist: _lidarrArtist,
  images: [],
  releaseDate: '2021-01-01',
);

const _pendingRequest = MusicRequest(
  id: 'req-1',
  type: 'artist',
  lidarrId: 42,
  name: 'Test Artist',
  status: 'pending',
  requestedAt: '2026-03-28T00:00:00Z',
);

const _downloadingRequest = MusicRequest(
  id: 'req-2',
  type: 'album',
  lidarrId: 10,
  name: 'Test Album',
  status: 'downloading',
  requestedAt: '2026-03-28T01:00:00Z',
);

const _availableRequest = MusicRequest(
  id: 'req-3',
  type: 'artist',
  lidarrId: 99,
  name: 'Another Artist',
  status: 'available',
  requestedAt: '2026-03-27T00:00:00Z',
);

// ---------------------------------------------------------------------------
// Widget helpers
// ---------------------------------------------------------------------------

Widget _buildSubject({
  required _MockSearchService searchService,
  SearchState? searchState,
  List<MusicRequest> requests = const [],
}) =>
    ProviderScope(
      overrides: [
        searchServiceProvider.overrideWith((_) => searchService),
        searchProvider.overrideWith(
          (ref) => _StubSearchNotifier(searchService, searchState),
        ),
        requestsProvider.overrideWith(() => _StubRequestsNotifier(requests)),
      ],
      child: const MaterialApp(home: SearchScreen()),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockSearchService mockSearchService;

  setUp(() {
    mockSearchService = _MockSearchService();
    when(() => mockSearchService.searchLibrary(any()))
        .thenAnswer((_) async => const SearchResults(artists: [], albums: []));
  });

  // ---------------------------------------------------------------------------
  // Basic rendering
  // ---------------------------------------------------------------------------

  testWidgets('renders search text field with hint', (tester) async {
    await tester.pumpWidget(_buildSubject(searchService: mockSearchService));
    expect(find.text('Search artists, albums...'), findsOneWidget);
  });

  testWidgets('renders Library, Request Music and My Requests tabs',
      (tester) async {
    await tester.pumpWidget(_buildSubject(searchService: mockSearchService));
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Request Music'), findsOneWidget);
    expect(find.text('My Requests'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Library tab
  // ---------------------------------------------------------------------------

  testWidgets('shows "Search your library" prompt when query is empty',
      (tester) async {
    await tester.pumpWidget(_buildSubject(searchService: mockSearchService));
    expect(find.text('Search your library'), findsOneWidget);
  });

  testWidgets('shows loading indicator while searching library', (tester) async {
    final state = const SearchState(
      query: 'test',
      isSearchingLibrary: true,
    );
    await tester.pumpWidget(
      _buildSubject(searchService: mockSearchService, searchState: state),
    );
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('shows library search results when available', (tester) async {
    final state = const SearchState(
      query: 'test',
      libraryResults: SearchResults(
        artists: [_testArtist],
        albums: [_testAlbum],
      ),
    );
    await tester.pumpWidget(
      _buildSubject(searchService: mockSearchService, searchState: state),
    );
    await tester.pump();

    expect(find.text('Test Artist'), findsWidgets);
    expect(find.text('Test Album'), findsOneWidget);
  });

  testWidgets('shows Artists and Albums section headers with results',
      (tester) async {
    final state = const SearchState(
      query: 'test',
      libraryResults: SearchResults(
        artists: [_testArtist],
        albums: [_testAlbum],
      ),
    );
    await tester.pumpWidget(
      _buildSubject(searchService: mockSearchService, searchState: state),
    );
    await tester.pump();

    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
  });

  testWidgets('shows album artist name as subtitle in library results',
      (tester) async {
    final state = const SearchState(
      query: 'test',
      libraryResults: SearchResults(
        artists: [],
        albums: [_testAlbum],
      ),
    );
    await tester.pumpWidget(
      _buildSubject(searchService: mockSearchService, searchState: state),
    );
    await tester.pump();

    expect(find.text('Test Artist'), findsOneWidget);
  });

  testWidgets('shows album count in artist subtitle', (tester) async {
    final state = const SearchState(
      query: 'test',
      libraryResults: SearchResults(
        artists: [_testArtist],
        albums: [],
      ),
    );
    await tester.pumpWidget(
      _buildSubject(searchService: mockSearchService, searchState: state),
    );
    await tester.pump();

    expect(find.text('3 albums'), findsOneWidget);
  });

  testWidgets('shows "No results" message when library has no matches',
      (tester) async {
    final state = const SearchState(
      query: 'unknownxyz',
      libraryResults: SearchResults(artists: [], albums: []),
    );
    await tester.pumpWidget(
      _buildSubject(searchService: mockSearchService, searchState: state),
    );
    await tester.pump();

    expect(find.textContaining('No results for'), findsOneWidget);
  });

  testWidgets('shows retry button on library search error', (tester) async {
    final state = const SearchState(
      query: 'test',
      libraryError: 'Network error',
    );
    await tester.pumpWidget(
      _buildSubject(searchService: mockSearchService, searchState: state),
    );
    await tester.pump();

    expect(find.text('Search failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('shows clear button when query is not empty', (tester) async {
    final state = const SearchState(query: 'test');
    await tester.pumpWidget(
      _buildSubject(searchService: mockSearchService, searchState: state),
    );
    await tester.pump();

    expect(find.byIcon(Icons.clear), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Request Music (Lidarr) tab
  // ---------------------------------------------------------------------------

  testWidgets('shows Lidarr empty state when query is empty', (tester) async {
    await tester.pumpWidget(_buildSubject(searchService: mockSearchService));

    // Tap the "Request Music" tab and wait for animation.
    await tester.tap(find.text('Request Music'));
    await tester.pumpAndSettle();

    expect(
      find.text('Type a query then tap "Search Lidarr"'),
      findsOneWidget,
    );
  });

  testWidgets('shows Search Lidarr button when query is set but not searched',
      (tester) async {
    final state = const SearchState(query: 'metal');
    await tester.pumpWidget(
      _buildSubject(searchService: mockSearchService, searchState: state),
    );
    await tester.tap(find.text('Request Music'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Search Lidarr for'), findsOneWidget);
  });

  testWidgets('shows Lidarr artists and albums when results available',
      (tester) async {
    final state = const SearchState(
      query: 'metal',
      lidarrResults: LidarrSearchResults(
        artists: [_lidarrArtist],
        albums: [_lidarrAlbum],
      ),
    );
    await tester.pumpWidget(
      _buildSubject(searchService: mockSearchService, searchState: state),
    );

    await tester.tap(find.text('Request Music'));
    await tester.pumpAndSettle();

    expect(find.text('Lidarr Artist'), findsWidgets);
    expect(find.text('Lidarr Album'), findsWidgets);
  });

  testWidgets('shows empty Lidarr state when results are empty', (tester) async {
    final state = const SearchState(
      query: 'unknownxyz',
      lidarrResults: LidarrSearchResults(artists: [], albums: []),
    );
    await tester.pumpWidget(
      _buildSubject(searchService: mockSearchService, searchState: state),
    );

    await tester.tap(find.text('Request Music'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No Lidarr results for'), findsOneWidget);
  });

  testWidgets('shows Lidarr search error with retry button', (tester) async {
    // Error state is only reached when lidarrResults is non-null (so the
    // "not yet searched" guard doesn't short-circuit).
    final state = const SearchState(
      query: 'test',
      lidarrError: 'Lidarr is down',
      lidarrResults: LidarrSearchResults(artists: [], albums: []),
    );
    await tester.pumpWidget(
      _buildSubject(searchService: mockSearchService, searchState: state),
    );

    await tester.tap(find.text('Request Music'));
    await tester.pumpAndSettle();

    expect(find.text('Lidarr search failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('shows loading indicator when searching Lidarr', (tester) async {
    final state = const SearchState(
      query: 'test',
      isSearchingLidarr: true,
    );
    await tester.pumpWidget(
      _buildSubject(searchService: mockSearchService, searchState: state),
    );

    await tester.tap(find.text('Request Music'));
    // Use pump() instead of pumpAndSettle() to avoid timeout from the spinner.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('shows Request button for Lidarr artist tiles', (tester) async {
    final state = const SearchState(
      query: 'metal',
      lidarrResults: LidarrSearchResults(
        artists: [_lidarrArtist],
        albums: [],
      ),
    );
    await tester.pumpWidget(
      _buildSubject(searchService: mockSearchService, searchState: state),
    );

    await tester.tap(find.text('Request Music'));
    await tester.pumpAndSettle();

    expect(find.text('Request'), findsWidgets);
  });

  testWidgets('shows Lidarr album release year when available', (tester) async {
    final state = const SearchState(
      query: 'metal',
      lidarrResults: LidarrSearchResults(
        artists: [],
        albums: [_lidarrAlbum],
      ),
    );
    await tester.pumpWidget(
      _buildSubject(searchService: mockSearchService, searchState: state),
    );

    await tester.tap(find.text('Request Music'));
    await tester.pumpAndSettle();

    // Album subtitle should contain artist name and year.
    expect(find.textContaining('Lidarr Artist'), findsOneWidget);
    expect(find.textContaining('2021'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // My Requests tab
  // ---------------------------------------------------------------------------

  testWidgets('shows "No pending requests" when requests list is empty',
      (tester) async {
    await tester.pumpWidget(
      _buildSubject(searchService: mockSearchService, requests: []),
    );
    await tester.tap(find.text('My Requests'));
    await tester.pumpAndSettle();

    expect(find.text('No pending requests'), findsOneWidget);
  });

  testWidgets('shows pending request in My Requests tab', (tester) async {
    await tester.pumpWidget(
      _buildSubject(
        searchService: mockSearchService,
        requests: [_pendingRequest],
      ),
    );
    await tester.tap(find.text('My Requests'));
    await tester.pumpAndSettle();

    expect(find.text('Test Artist'), findsWidgets);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('shows Downloading badge for downloading request', (tester) async {
    await tester.pumpWidget(
      _buildSubject(
        searchService: mockSearchService,
        requests: [_downloadingRequest],
      ),
    );
    await tester.tap(find.text('My Requests'));
    await tester.pumpAndSettle();

    expect(find.text('Downloading'), findsOneWidget);
  });

  testWidgets('shows Available badge for available request', (tester) async {
    await tester.pumpWidget(
      _buildSubject(
        searchService: mockSearchService,
        requests: [_availableRequest],
      ),
    );
    await tester.tap(find.text('My Requests'));
    await tester.pumpAndSettle();

    expect(find.text('Available'), findsOneWidget);
  });

  testWidgets('shows multiple requests in list', (tester) async {
    await tester.pumpWidget(
      _buildSubject(
        searchService: mockSearchService,
        requests: [_pendingRequest, _downloadingRequest, _availableRequest],
      ),
    );
    await tester.tap(find.text('My Requests'));
    await tester.pumpAndSettle();

    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Downloading'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
  });
}
