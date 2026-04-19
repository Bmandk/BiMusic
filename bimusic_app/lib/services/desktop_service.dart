import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/material.dart' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/minimize_to_tray_provider.dart';

class DesktopService with WindowListener, TrayListener {
  DesktopService._();
  static final DesktopService instance = DesktopService._();

  ProviderContainer? _container;
  ProviderSubscription<bool>? _minimizeToTraySub;

  Future<void> init(
    ProviderContainer container, {
    required bool startHidden,
  }) async {
    _container = container;

    await windowManager.ensureInitialized();

    const options = WindowOptions(
      minimumSize: Size(400, 300),
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      if (startHidden) {
        await windowManager.setSkipTaskbar(true);
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });

    // Set up autostart registration (enable/disable is handled by the notifier).
    final pkgInfo = await PackageInfo.fromPlatform();
    LaunchAtStartup.instance.setup(
      appName: pkgInfo.appName.isNotEmpty ? pkgInfo.appName : 'BiMusic',
      appPath: Platform.resolvedExecutable,
      packageName: pkgInfo.packageName.isNotEmpty
          ? pkgInfo.packageName
          : 'com.bimusic.bimusic_app',
      args: const ['--hidden'],
    );

    // Set up tray icon and menu.
    await trayManager.setIcon(
      Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png',
    );
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show_hide', label: 'Show / Hide'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]));

    // Register listeners.
    windowManager.addListener(this);
    trayManager.addListener(this);

    // Apply initial close-interception preference.
    final initialPref = container.read(minimizeToTrayProvider);
    await windowManager.setPreventClose(initialPref);

    // React to future preference changes.
    _minimizeToTraySub = container.listen<bool>(
      minimizeToTrayProvider,
      (_, next) => unawaited(onMinimizeToTrayChanged(next)),
    );
  }

  Future<void> showWindow() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hideWindow() async {
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }

  Future<void> quit() async {
    _minimizeToTraySub?.close();
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<void> onMinimizeToTrayChanged(bool enabled) async {
    await windowManager.setPreventClose(enabled);
    if (!enabled) {
      final isVisible = await windowManager.isVisible();
      if (!isVisible) await showWindow();
    }
  }

  // ---------------------------------------------------------------------------
  // WindowListener
  // ---------------------------------------------------------------------------

  @override
  void onWindowClose() {
    unawaited(_handleClose());
  }

  Future<void> _handleClose() async {
    // Fires only when setPreventClose(true) is active.
    final pref = _container?.read(minimizeToTrayProvider) ?? true;
    if (pref) {
      await hideWindow();
    } else {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    }
  }

  @override
  void onWindowMinimize() {
    unawaited(_handleMinimize());
  }

  Future<void> _handleMinimize() async {
    final pref = _container?.read(minimizeToTrayProvider) ?? true;
    if (pref) {
      await windowManager.hide();
      await windowManager.setSkipTaskbar(true);
    }
  }

  // ---------------------------------------------------------------------------
  // TrayListener
  // ---------------------------------------------------------------------------

  @override
  void onTrayIconMouseDown() {
    unawaited(showWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_hide':
        unawaited(_handleShowHideToggle());
      case 'quit':
        unawaited(quit());
    }
  }

  Future<void> _handleShowHideToggle() async {
    final visible = await windowManager.isVisible();
    if (visible) {
      await hideWindow();
    } else {
      await showWindow();
    }
  }
}
