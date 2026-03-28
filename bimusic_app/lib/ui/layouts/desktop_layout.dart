import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DesktopLayout extends StatelessWidget {
  const DesktopLayout({
    super.key,
    required this.navigationShell,
    required this.child,
  });

  final StatefulNavigationShell navigationShell;
  final Widget child;

  static const List<({IconData icon, IconData selectedIcon, String label})>
      _destinations = [
    (
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: 'Home',
    ),
    (
      icon: Icons.library_music_outlined,
      selectedIcon: Icons.library_music,
      label: 'Library',
    ),
    (
      icon: Icons.search,
      selectedIcon: Icons.search,
      label: 'Search',
    ),
    (
      icon: Icons.queue_music_outlined,
      selectedIcon: Icons.queue_music,
      label: 'Playlists',
    ),
    (
      icon: Icons.download_outlined,
      selectedIcon: Icons.download,
      label: 'Downloads',
    ),
    (
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedIndex = navigationShell.currentIndex;

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 220,
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      for (int i = 0; i < _destinations.length; i++)
                        ListTile(
                          leading: Icon(
                            i == selectedIndex
                                ? _destinations[i].selectedIcon
                                : _destinations[i].icon,
                          ),
                          title: Text(_destinations[i].label),
                          selected: i == selectedIndex,
                          selectedColor: theme.colorScheme.primary,
                          onTap: () => navigationShell.goBranch(i),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            ),
          ),
          Container(
            height: 80,
            color: theme.colorScheme.surface,
            child: const Center(child: Text('Player Controls')),
          ),
        ],
      ),
    );
  }
}
