import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/services/github_release_client.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() {
    registerFallbackValue(Options());
    registerFallbackValue(RequestOptions(path: ''));
  });

  group('GitHubReleaseClient', () {
    late _MockDio dio;
    late GitHubReleaseClient client;

    setUp(() {
      dio = _MockDio();
      client = GitHubReleaseClient(dio);
    });

    test('fetchLatest calls correct endpoint with GitHub Accept header',
        () async {
      const expectedUrl =
          'https://api.github.com/repos/Bmandk/BiMusic/releases/latest';
      when(() => dio.get<Map<String, dynamic>>(
            any(),
            options: any(named: 'options'),
          )).thenAnswer((_) async => Response(
            data: {'tag_name': 'app-v1.1.0', 'assets': []},
            statusCode: 200,
            requestOptions: RequestOptions(path: expectedUrl),
          ));

      final result = await client.fetchLatest();

      expect(result['tag_name'], 'app-v1.1.0');

      final captured = verify(() => dio.get<Map<String, dynamic>>(
            captureAny(),
            options: captureAny(named: 'options'),
          )).captured;

      expect(captured[0], contains('Bmandk/BiMusic'));
      final opts = captured[1] as Options;
      expect(opts.headers?['Accept'], contains('github'));
    });

    test('fetchLatest returns the response data map', () async {
      final payload = {
        'tag_name': 'app-v2.0.0',
        'body': 'Big release',
        'html_url': 'https://github.com',
        'assets': <dynamic>[],
      };
      when(() => dio.get<Map<String, dynamic>>(
            any(),
            options: any(named: 'options'),
          )).thenAnswer((_) async => Response(
            data: payload,
            statusCode: 200,
            requestOptions: RequestOptions(path: ''),
          ));

      final result = await client.fetchLatest();
      expect(result, payload);
    });

    test('fetchLatest propagates DioException on network failure', () async {
      when(() => dio.get<Map<String, dynamic>>(
            any(),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionTimeout,
      ));

      expect(() => client.fetchLatest(), throwsA(isA<DioException>()));
    });
  });
}
