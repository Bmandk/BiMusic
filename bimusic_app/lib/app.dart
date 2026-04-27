import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/theme.dart';
import 'providers/backend_url_provider.dart';
import 'providers/player_provider.dart';
import 'router.dart';
import 'ui/screens/backend_setup_screen.dart';
import 'ui/widgets/update_launch_listener.dart';

class BiMusicApp extends ConsumerWidget {
  const BiMusicApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlState = ref.watch(backendUrlProvider);

    Widget app = urlState.when(
      loading: () => MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      error: (e, _) => MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: BackendSetupScreen(initialError: '$e'),
      ),
      data: (url) => url == null
          ? MaterialApp(
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: ThemeMode.system,
              home: const BackendSetupScreen(),
            )
          : UpdateLaunchListener(
              child: MaterialApp.router(
                title: 'BiMusic',
                theme: AppTheme.light,
                darkTheme: AppTheme.dark,
                themeMode: ThemeMode.system,
                routerConfig: ref.watch(routerProvider),
                builder: (context, child) => Consumer(
                  builder: (context, ref, _) => CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.space): () {
                        final playerState = ref.read(playerNotifierProvider);
                        if (!playerState.hasTrack) return;
                        final notifier =
                            ref.read(playerNotifierProvider.notifier);
                        if (playerState.isPlaying) {
                          notifier.pause();
                        } else {
                          notifier.resume();
                        }
                      },
                    },
                    child: Focus(
                      autofocus: true,
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
    );

    // coverage:ignore-start
    // Work around a Flutter Windows accessibility bridge bug where
    // OverlayPortal semantics nodes get reparented on any tree change,
    // causing "Failed to update ui::AXTree" errors in the engine.
    if (!kIsWeb && Platform.isWindows) {
      app = ExcludeSemantics(child: app);
    }
    // coverage:ignore-end

    return app;
  }
}
