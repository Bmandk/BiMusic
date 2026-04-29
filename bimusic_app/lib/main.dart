// coverage:ignore-file
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'app.dart';
import 'providers/launch_at_startup_provider.dart';
import 'services/audio_service.dart';
import 'services/desktop_service.dart';
import 'utils/platform.dart';

// ---------------------------------------------------------------------------
// Background service (mobile only)
// ---------------------------------------------------------------------------

/// Entry point for the background service isolate.
/// The service keeps the process alive so in-progress downloads continue when
/// the app moves to background on Android/iOS.
@pragma('vm:entry-point')
void _backgroundServiceMain(ServiceInstance service) {
  service.on('stop').listen((_) => service.stopSelf());
}

/// iOS background handler — must return true to keep the service alive.
@pragma('vm:entry-point')
Future<bool> _iosBackgroundHandler(ServiceInstance service) async => true;

Future<void> _initBackgroundService() async {
  final bgService = FlutterBackgroundService();
  await bgService.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _backgroundServiceMain,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      notificationChannelId: 'bimusic_downloads',
      initialNotificationTitle: 'BiMusic Downloads',
      initialNotificationContent: 'Processing downloads…',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: _backgroundServiceMain,
      onBackground: _iosBackgroundHandler,
    ),
  );
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Reduce libmpv demuxer buffer from the default 32 MB to 2 MB to cut
  // initial prebuffer time on Windows/Linux without risking glitches on LAN.
  // media_kit backend is only active on desktop platforms.
  if (isDesktop) {
    JustAudioMediaKit.bufferSize = 2 * 1024 * 1024;
    JustAudioMediaKit.ensureInitialized();
  }

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await _initBackgroundService();
  }

  final audioHandler = await AudioService.init<BiMusicAudioHandler>(
    builder: BiMusicAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.bimusic.audio',
      androidNotificationChannelName: 'BiMusic Audio',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  final container = ProviderContainer(
    overrides: [audioHandlerProvider.overrideWithValue(audioHandler)],
  );

  if (isDesktop) {
    final startHidden = args.contains('--hidden');
    await DesktopService.instance.init(container, startHidden: startHidden);
    await container.read(launchAtStartupProvider.notifier).syncWithOs();
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const BiMusicApp(),
    ),
  );
}
