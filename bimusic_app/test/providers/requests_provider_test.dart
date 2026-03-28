import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/models/music_request.dart';
import 'package:bimusic_app/providers/requests_provider.dart';
import 'package:bimusic_app/services/search_service.dart';

class MockSearchService extends Mock implements SearchService {}

void main() {
  late MockSearchService mockService;
  late ProviderContainer container;

  const testRequest = MusicRequest(
    id: 'req-1',
    type: 'artist',
    lidarrId: 42,
    status: 'pending',
    requestedAt: '2026-03-28T00:00:00Z',
  );

  const testRequest2 = MusicRequest(
    id: 'req-2',
    type: 'album',
    lidarrId: 10,
    status: 'available',
    requestedAt: '2026-03-28T01:00:00Z',
  );

  setUp(() {
    mockService = MockSearchService();
    container = ProviderContainer(
      overrides: [
        searchServiceProvider.overrideWith((_) => mockService),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('requestsProvider', () {
    test('build loads requests on first access', () async {
      when(() => mockService.getRequests())
          .thenAnswer((_) async => [testRequest]);

      final result = await container.read(requestsProvider.future);

      expect(result, hasLength(1));
      expect(result.first.id, 'req-1');
      expect(result.first.type, 'artist');
      verify(() => mockService.getRequests()).called(1);
    });

    test('build returns empty list when no requests', () async {
      when(() => mockService.getRequests()).thenAnswer((_) async => []);

      final result = await container.read(requestsProvider.future);

      expect(result, isEmpty);
    });

    test('refresh reloads requests', () async {
      when(() => mockService.getRequests())
          .thenAnswer((_) async => [testRequest]);

      await container.read(requestsProvider.future);
      expect(container.read(requestsProvider).value, hasLength(1));

      when(() => mockService.getRequests())
          .thenAnswer((_) async => [testRequest, testRequest2]);

      await container.read(requestsProvider.notifier).refresh();

      expect(container.read(requestsProvider).value, hasLength(2));
    });

    test('refresh transitions through loading state', () async {
      when(() => mockService.getRequests())
          .thenAnswer((_) async => [testRequest]);
      await container.read(requestsProvider.future);

      final loadingStates = <bool>[];
      container.listen(
        requestsProvider,
        (_, next) => loadingStates.add(next.isLoading),
      );

      when(() => mockService.getRequests())
          .thenAnswer((_) async => [testRequest2]);

      await container.read(requestsProvider.notifier).refresh();

      expect(loadingStates, contains(true));
    });
  });
}
