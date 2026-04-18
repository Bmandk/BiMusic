import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;

import '../models/update_info.dart';
import '../services/github_release_client.dart';
import '../services/update_installer.dart';

/// Resolves the installed app's semver. Override in tests to avoid platform-channel calls.
@visibleForTesting
final currentVersionProvider = FutureProvider<SemVer>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return SemVer.tryParse(info.version) ?? const SemVer(0, 0, 0);
});

// ---------------------------------------------------------------------------
// State types
// ---------------------------------------------------------------------------

sealed class UpdateState {
  const UpdateState();
}

class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

class UpdateAvailable extends UpdateState {
  const UpdateAvailable(this.info);
  final UpdateInfo info;
}

class UpdateUpToDate extends UpdateState {
  const UpdateUpToDate();
}

class UpdateDownloading extends UpdateState {
  const UpdateDownloading(this.info, this.progress);
  final UpdateInfo info;
  final double progress;
}

class UpdateInstalled extends UpdateState {
  const UpdateInstalled();
}

class UpdateError extends UpdateState {
  const UpdateError(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class UpdateNotifier extends Notifier<UpdateState> {
  CancelToken? _cancelToken;
  bool _launchCheckRan = false;

  @override
  UpdateState build() => const UpdateIdle();

  /// Runs at most once per app session. Errors are silenced.
  Future<void> checkOnLaunch() async {
    if (_launchCheckRan) return;
    _launchCheckRan = true;
    await _doCheck(silent: true);
  }

  /// Always re-runs the check. Errors surface as [UpdateError].
  Future<void> checkManual() async {
    await _doCheck(silent: false);
  }

  Future<void> _doCheck({required bool silent}) async {
    state = const UpdateChecking();
    try {
      final currentSemVer = await ref.read(currentVersionProvider.future);
      final client = ref.read(githubReleaseClientProvider);
      final data = await client.fetchLatest();
      final info = UpdateInfo.fromGitHubRelease(data, currentSemVer);
      state = info.updateAvailable
          ? UpdateAvailable(info)
          : const UpdateUpToDate();
    } catch (e) {
      state = silent ? const UpdateIdle() : UpdateError(_friendlyError(e));
    }
  }

  /// Begins the platform-specific download and install. No-op unless the
  /// current state is [UpdateAvailable].
  Future<void> installNow() async {
    final current = state;
    if (current is! UpdateAvailable) return;
    final info = current.info;
    _cancelToken = CancelToken();
    state = UpdateDownloading(info, 0.0);
    try {
      final installer = ref.read(updateInstallerProvider);
      await installer.downloadAndInstall(
        info,
        onProgress: (p) => state = UpdateDownloading(info, p),
        cancelToken: _cancelToken,
      );
      // Windows calls exit(0) inside downloadAndInstall, so we never reach here.
      state = const UpdateInstalled();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        state = UpdateAvailable(info);
      } else {
        state = UpdateError('Download failed: ${e.message}');
      }
    } catch (e) {
      state = UpdateError(e.toString());
    } finally {
      _cancelToken = null;
    }
  }

  /// Cancels an in-progress download. State returns to [UpdateAvailable].
  void cancelDownload() {
    _cancelToken?.cancel();
  }

  /// Returns state to [UpdateIdle] without dismissing the update permanently.
  void dismiss() {
    state = const UpdateIdle();
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('rate limit') || msg.contains('403')) {
      return 'Rate limited — try again later.';
    }
    if (e is DioException) return 'Network error: ${e.message}';
    return msg;
  }
}

final updateProvider =
    NotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);
