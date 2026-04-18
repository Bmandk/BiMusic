import 'dart:io' show Directory, File, Platform, Process, ProcessStartMode, exit, pid;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/update_info.dart';
import 'github_release_client.dart';

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

abstract class UpdateInstaller {
  Future<void> downloadAndInstall(
    UpdateInfo info, {
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  });
}

// ---------------------------------------------------------------------------
// Android implementation
// ---------------------------------------------------------------------------

class AndroidUpdateInstaller implements UpdateInstaller {
  const AndroidUpdateInstaller(this._dio);

  final Dio _dio;

  @override
  Future<void> downloadAndInstall(
    UpdateInfo info, {
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    final url = info.apkAssetUrl;
    if (url == null || url.isEmpty) {
      throw Exception('No APK asset found in this release.');
    }

    final externalDir = await getExternalStorageDirectory();
    final baseDir =
        externalDir?.path ?? (await getApplicationDocumentsDirectory()).path;
    final updatesDir = Directory('$baseDir/updates');
    await updatesDir.create(recursive: true);

    // Best-effort cleanup of old APK files.
    await for (final entity in updatesDir.list()) {
      if (entity is File && entity.path.endsWith('.apk')) {
        await entity.delete().catchError((_) => entity);
      }
    }

    final version = info.latestVersion.toString();
    final apkPath = '${updatesDir.path}/bimusic-$version.apk';

    await _dio.download(
      url,
      apkPath,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress(received / total);
      },
    );

    // Verify downloaded size matches the manifest if known.
    final expectedSize = info.apkAssetSize;
    if (expectedSize != null) {
      final actualSize = await File(apkPath).length();
      if (actualSize != expectedSize) {
        await File(apkPath).delete();
        throw Exception('Downloaded APK size mismatch. Please try again.');
      }
    }

    final result = await OpenFilex.open(
      apkPath,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw Exception('Could not launch installer: ${result.message}');
    }
  }
}

// ---------------------------------------------------------------------------
// Windows implementation
// ---------------------------------------------------------------------------

class WindowsUpdateInstaller implements UpdateInstaller {
  const WindowsUpdateInstaller(this._dio);

  final Dio _dio;

  @override
  Future<void> downloadAndInstall(
    UpdateInfo info, {
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    final url = info.windowsAssetUrl;
    if (url == null || url.isEmpty) {
      throw Exception('No Windows asset found in this release.');
    }

    final installDir = File(Platform.resolvedExecutable).parent.path;

    // Probe writability before starting the download.
    final probeFile = File('$installDir/.bimusic_update_probe');
    try {
      await probeFile.writeAsString('probe');
      await probeFile.delete();
    } catch (_) {
      throw Exception(
        'Cannot update automatically: BiMusic is installed in a protected '
        'directory (e.g. Program Files). Please download and install the new '
        'version manually from the release page.',
      );
    }

    final tmpDir = (await getTemporaryDirectory()).path;
    final suffix = DateTime.now().millisecondsSinceEpoch;
    final zipPath = '$tmpDir/bimusic_update_$suffix.zip';
    final scriptPath = '$tmpDir/bimusic_update_$suffix.ps1';

    await _dio.download(
      url,
      zipPath,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress(received / total);
      },
    );

    final expectedSize = info.windowsAssetSize;
    if (expectedSize != null) {
      final actualSize = await File(zipPath).length();
      if (actualSize != expectedSize) {
        await File(zipPath).delete();
        throw Exception('Downloaded ZIP size mismatch. Please try again.');
      }
    }

    final exeName = File(Platform.resolvedExecutable).uri.pathSegments.last;
    final currentPid = pid;
    final scriptBody = buildPowerShellScriptBody();
    await File(scriptPath).writeAsString(scriptBody);

    await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        scriptPath,
        '-ParentPid',
        '$currentPid',
        '-ZipPath',
        zipPath,
        '-InstallDir',
        installDir,
        '-ExeName',
        exeName,
      ],
      mode: ProcessStartMode.detached,
    );

    // Exit so the PowerShell script can overwrite the running exe and DLLs.
    exit(0);
  }

  @visibleForTesting
  static String buildPowerShellScriptBody() => r'''
param(
  [int]$ParentPid,
  [string]$ZipPath,
  [string]$InstallDir,
  [string]$ExeName
)
$ErrorActionPreference = 'Stop'
$staging = $null
try {
  for ($i = 0; $i -lt 60; $i++) {
    if (-not (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 500
  }
  $staging = Join-Path $env:TEMP ("bimusic_stage_" + [guid]::NewGuid())
  Expand-Archive -Path $ZipPath -DestinationPath $staging -Force
  $srcRoot = Get-ChildItem $staging -Directory | Select-Object -First 1 -ExpandProperty FullName
  if (-not $srcRoot) { $srcRoot = $staging }
  Copy-Item -Path (Join-Path $srcRoot '*') -Destination $InstallDir -Recurse -Force
  Start-Process -FilePath (Join-Path $InstallDir $ExeName)
} catch {
  $_ | Out-File -FilePath (Join-Path $env:TEMP 'bimusic_update_error.log') -Append
} finally {
  Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
  if ($staging) { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
}
''';
}

// ---------------------------------------------------------------------------
// Fallback: open release page in browser
// ---------------------------------------------------------------------------

class UnsupportedUpdateInstaller implements UpdateInstaller {
  const UnsupportedUpdateInstaller();

  @override
  Future<void> downloadAndInstall(
    UpdateInfo info, {
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    final uri = Uri.tryParse(info.releaseUrl);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final updateInstallerProvider = Provider<UpdateInstaller>((ref) {
  if (kIsWeb) return const UnsupportedUpdateInstaller();
  final dio = ref.watch(updateDioProvider);
  if (Platform.isAndroid) return AndroidUpdateInstaller(dio);
  if (Platform.isWindows) return WindowsUpdateInstaller(dio);
  return const UnsupportedUpdateInstaller();
});
