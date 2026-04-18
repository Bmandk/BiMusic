import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GitHubReleaseClient {
  GitHubReleaseClient(this._dio);

  final Dio _dio;

  static const _endpoint =
      'https://api.github.com/repos/Bmandk/BiMusic/releases/latest';

  Future<Map<String, dynamic>> fetchLatest() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      _endpoint,
      options: Options(headers: {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      }),
    );
    return resp.data!;
  }
}

// Vanilla Dio — no base URL or auth interceptors so JWT is never sent to GitHub.
final updateDioProvider = Provider<Dio>((_) => Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    )));

final githubReleaseClientProvider = Provider<GitHubReleaseClient>(
  (ref) => GitHubReleaseClient(ref.watch(updateDioProvider)),
);
