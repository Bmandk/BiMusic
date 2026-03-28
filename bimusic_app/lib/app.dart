import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/theme.dart';
import 'router.dart';

class BiMusicApp extends ConsumerWidget {
  const BiMusicApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget app = MaterialApp.router(
      title: 'BiMusic',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
    );

    // Work around a Flutter Windows accessibility bridge bug where
    // OverlayPortal semantics nodes get reparented on any tree change,
    // causing "Failed to update ui::AXTree" errors in the engine.
    if (Platform.isWindows) {
      app = ExcludeSemantics(child: app);
    }

    return app;
  }
}
