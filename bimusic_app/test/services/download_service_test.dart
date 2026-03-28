import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/services/download_service.dart';

// ---------------------------------------------------------------------------
// Fake Dio for download
// ---------------------------------------------------------------------------

typedef _DownloadHandler = Future<void> Function(
  String urlPath,
  dynamic savePath,
  ProgressCallback? onReceiveProgress,
  CancelToken? cancelToken,
);

class _FakeDio extends Fake implements Dio {
  final List<_DownloadHandler> _handlers;
  int callCount = 0;

  _FakeDio(this._handlers);

  @override
  Future<Response<dynamic>> download(
    String urlPath,
    dynamic savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    ProgressCallback? onSendProgress,
    String lengthHeader = Headers.contentLengthHeader,
    Object? data,
    Options? options,
    FileAccessMode? fileAccessMode,
  }) async {
    final handler = _handlers[callCount++];
    await handler(urlPath, savePath, onReceiveProgress, cancelToken);
    return Response<dynamic>(
      requestOptions: RequestOptions(path: urlPath),
      statusCode: 200,
    );
  }
}

DioException _make409(String path) => DioException(
      requestOptions: RequestOptions(path: path),
      response: Response<dynamic>(
        statusCode: 409,
        requestOptions: RequestOptions(path: path),
      ),
      type: DioExceptionType.badResponse,
    );

DioException _make500(String path) => DioException(
      requestOptions: RequestOptions(path: path),
      response: Response<dynamic>(
        statusCode: 500,
        requestOptions: RequestOptions(path: path),
      ),
      type: DioExceptionType.badResponse,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('generateUuid', () {
    test('returns a string in UUID v4 format', () {
      final id = generateUuid();
      // UUID v4: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
      final uuidPattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(uuidPattern.hasMatch(id), isTrue, reason: 'Got: $id');
    });

    test('generates unique values each time', () {
      final ids = List.generate(10, (_) => generateUuid());
      expect(ids.toSet(), hasLength(10));
    });
  });

  group('DownloadService.downloadFile', () {
    test('succeeds on first attempt and calls progress callback', () async {
      double? reportedProgress;

      final fakeDio = _FakeDio([
        (urlPath, savePath, onReceiveProgress, cancelToken) async {
          onReceiveProgress?.call(50, 100);
          onReceiveProgress?.call(100, 100);
        },
      ]);
      final service = DownloadService(fakeDio);

      await service.downloadFile(
        serverId: 'srv-1',
        savePath: '/tmp/test.mp3',
        onProgress: (p) => reportedProgress = p,
      );

      expect(reportedProgress, 1.0);
      expect(fakeDio.callCount, 1);
    });

    test('propagates non-409 DioException immediately', () async {
      final fakeDio = _FakeDio([
        (urlPath, savePath, onReceiveProgress, cancelToken) async {
          throw _make500(urlPath);
        },
      ]);
      final service = DownloadService(fakeDio);

      expect(
        () => service.downloadFile(
          serverId: 'srv-err',
          savePath: '/tmp/err.mp3',
          onProgress: (_) {},
        ),
        throwsA(isA<DioException>()),
      );
    });

    test('throws on cancel token cancellation', () async {
      final cancelToken = CancelToken();

      final fakeDio = _FakeDio([
        (urlPath, savePath, onReceiveProgress, ct) async {
          throw DioException(
            requestOptions: RequestOptions(path: urlPath),
            type: DioExceptionType.cancel,
          );
        },
      ]);
      final service = DownloadService(fakeDio);

      cancelToken.cancel();

      expect(
        () => service.downloadFile(
          serverId: 'srv-cancel',
          savePath: '/tmp/cancel.mp3',
          onProgress: (_) {},
          cancelToken: cancelToken,
        ),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('deviceIdProvider', () {
    // deviceIdProvider uses FlutterSecureStorage (platform channel).
    // It is tested indirectly via download_provider_test overrides.
    // Only the pure UUID logic is tested here.
    test('generateUuid produces valid hyphenated format', () {
      for (var i = 0; i < 5; i++) {
        final id = generateUuid();
        expect(id.split('-'), hasLength(5));
        expect(id.length, 36);
      }
    });
  });
}
