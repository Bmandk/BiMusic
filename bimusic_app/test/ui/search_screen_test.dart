import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/models/music_request.dart';
import 'package:bimusic_app/providers/requests_provider.dart';
import 'package:bimusic_app/providers/search_provider.dart';
import 'package:bimusic_app/services/search_service.dart';
import 'package:bimusic_app/ui/screens/search_screen.dart';

class _MockSearchService extends Mock implements SearchService {}

class _StubSearchNotifier extends SearchNotifier {
  _StubSearchNotifier(super.searchService);
}

class _StubRequestsNotifier extends RequestsNotifier {
  @override
  Future<List<MusicRequest>> build() async => [];
}

void main() {
  late _MockSearchService mockSearchService;

  setUp(() {
    mockSearchService = _MockSearchService();
  });

  Widget buildSubject() => ProviderScope(
        overrides: [
          searchServiceProvider.overrideWith((_) => mockSearchService),
          searchProvider
              .overrideWith((ref) => _StubSearchNotifier(mockSearchService)),
          requestsProvider.overrideWith(() => _StubRequestsNotifier()),
        ],
        child: const MaterialApp(home: SearchScreen()),
      );

  testWidgets('renders search text field with hint', (tester) async {
    await tester.pumpWidget(buildSubject());
    expect(find.text('Search artists, albums...'), findsOneWidget);
  });

  testWidgets('renders Library, Request Music and My Requests tabs',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Request Music'), findsOneWidget);
    expect(find.text('My Requests'), findsOneWidget);
  });

  testWidgets('shows "Search your library" prompt when query is empty',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    expect(find.text('Search your library'), findsOneWidget);
  });
}
