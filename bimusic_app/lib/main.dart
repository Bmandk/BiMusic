import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/audio_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final audioHandler = await AudioService.init<BiMusicAudioHandler>(
    builder: BiMusicAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.bimusic.audio',
      androidNotificationChannelName: 'BiMusic Audio',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const BiMusicApp(),
    ),
  );
}
