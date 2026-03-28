import 'package:flutter/material.dart';

import 'config/theme.dart';
import 'router.dart';

class BiMusicApp extends StatelessWidget {
  const BiMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'BiMusic',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: AppRouter.router,
    );
  }
}
