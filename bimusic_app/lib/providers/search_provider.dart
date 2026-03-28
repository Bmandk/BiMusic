import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lidarr_search_results.dart';
import '../models/search_results.dart';
import '../services/search_service.dart';

// ---------------------------------------------------------------------------
// Request submission status per item
// ---------------------------------------------------------------------------

enum RequestSubmitStatus { idle, submitting, submitted, error }

// ---------------------------------------------------------------------------
// Search state
// ---------------------------------------------------------------------------

class SearchState {
  const SearchState({
    this.query = '',
    this.libraryResults,
    this.lidarrResults,
    this.isSearchingLibrary = false,
    this.isSearchingLidarr = false,
    this.libraryError,
    this.lidarrError,
    this.requestStatuses = const {},
  });

  final String query;

  /// Library results (`null` = not yet searched or query cleared).
  final SearchResults? libraryResults;

  /// Lidarr lookup results (`null` = not yet searched).
  final LidarrSearchResults? lidarrResults;

  final bool isSearchingLibrary;
  final bool isSearchingLidarr;
  final String? libraryError;
  final String? lidarrError;

  // Key: "artist:<lidarrId>" or "album:<lidarrId>"
  final Map<String, RequestSubmitStatus> requestStatuses;

  SearchState copyWith({
    String? query,
    SearchResults? Function()? libraryResults,
    LidarrSearchResults? Function()? lidarrResults,
    bool? isSearchingLibrary,
    bool? isSearchingLidarr,
    String? Function()? libraryError,
    String? Function()? lidarrError,
    Map<String, RequestSubmitStatus>? requestStatuses,
  }) {
    return SearchState(
      query: query ?? this.query,
      libraryResults:
          libraryResults != null ? libraryResults() : this.libraryResults,
      lidarrResults:
          lidarrResults != null ? lidarrResults() : this.lidarrResults,
      isSearchingLibrary: isSearchingLibrary ?? this.isSearchingLibrary,
      isSearchingLidarr: isSearchingLidarr ?? this.isSearchingLidarr,
      libraryError: libraryError != null ? libraryError() : this.libraryError,
      lidarrError: lidarrError != null ? lidarrError() : this.lidarrError,
      requestStatuses: requestStatuses ?? this.requestStatuses,
    );
  }
}

// ---------------------------------------------------------------------------
// SearchNotifier
// ---------------------------------------------------------------------------

class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier(this._searchService) : super(const SearchState());

  final SearchService _searchService;
  Timer? _debounce;

  /// Update the search query. Library search is debounced 300 ms.
  /// Clears Lidarr results when the query changes.
  void setQuery(String query) {
    _debounce?.cancel();
    if (query.isEmpty) {
      state = const SearchState();
      return;
    }
    state = state.copyWith(
      query: query,
      lidarrResults: () => null,
      lidarrError: () => null,
    );
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _searchLibrary(query);
    });
  }

  Future<void> _searchLibrary(String query) async {
    state = state.copyWith(
      isSearchingLibrary: true,
      libraryError: () => null,
    );
    try {
      final results = await _searchService.searchLibrary(query);
      // Guard against a stale response arriving after the query changed.
      if (state.query != query) return;
      state = state.copyWith(
        libraryResults: () => results,
        isSearchingLibrary: false,
      );
    } catch (e) {
      if (state.query != query) return;
      state = state.copyWith(
        isSearchingLibrary: false,
        libraryError: () => e.toString(),
      );
    }
  }

  /// Manually trigger a Lidarr search for the current query.
  Future<void> searchLidarr() async {
    final query = state.query;
    if (query.isEmpty) return;
    state = state.copyWith(
      isSearchingLidarr: true,
      lidarrError: () => null,
    );
    try {
      final results = await _searchService.searchLidarr(query);
      state = state.copyWith(
        lidarrResults: () => results,
        isSearchingLidarr: false,
      );
    } catch (e) {
      state = state.copyWith(
        isSearchingLidarr: false,
        lidarrError: () => e.toString(),
      );
    }
  }

  /// Submit a request for a Lidarr artist.
  Future<void> requestArtist(LidarrArtistResult artist) async {
    final key = 'artist:${artist.id}';
    _setRequestStatus(key, RequestSubmitStatus.submitting);
    try {
      final foreignId = artist.foreignArtistId;
      if (foreignId == null || foreignId.isEmpty) {
        _setRequestStatus(key, RequestSubmitStatus.error);
        return;
      }
      await _searchService.requestArtist(
        foreignArtistId: foreignId,
        artistName: artist.artistName,
      );
      _setRequestStatus(key, RequestSubmitStatus.submitted);
    } catch (_) {
      _setRequestStatus(key, RequestSubmitStatus.error);
    }
  }

  /// Submit a request for a Lidarr album.
  Future<void> requestAlbum(LidarrAlbumResult album) async {
    final key = 'album:${album.id}';
    _setRequestStatus(key, RequestSubmitStatus.submitting);
    try {
      await _searchService.requestAlbum(album.id);
      _setRequestStatus(key, RequestSubmitStatus.submitted);
    } catch (_) {
      _setRequestStatus(key, RequestSubmitStatus.error);
    }
  }

  void _setRequestStatus(String key, RequestSubmitStatus status) {
    state = state.copyWith(
      requestStatuses: {...state.requestStatuses, key: status},
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final searchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(ref.watch(searchServiceProvider));
});
