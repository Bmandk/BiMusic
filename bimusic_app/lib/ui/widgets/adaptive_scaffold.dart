import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../layouts/breakpoints.dart';
import '../layouts/desktop_layout.dart';
import '../layouts/mobile_layout.dart';

class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    required this.navigationShell,
    required this.child,
  });

  final StatefulNavigationShell navigationShell;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= Breakpoints.desktop) {
      return DesktopLayout(navigationShell: navigationShell, child: child);
    }
    return MobileLayout(navigationShell: navigationShell, child: child);
  }
}
