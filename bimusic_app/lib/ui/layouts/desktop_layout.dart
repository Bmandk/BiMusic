import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/player_provider.dart';
import '../widgets/player_bar.dart';

class DesktopLayout extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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
                  child: SingleChildScrollView(
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
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            ),
          ),
          Consumer(
            builder: (context, ref, _) {
              final hasTrack = ref.watch(
                playerNotifierProvider.select((s) => s.hasTrack),
              );
              if (!hasTrack) return const SizedBox.shrink();
              return const SizedBox(height: 80, child: PlayerBar());
            },
          ),
        ],
      ),
    );
  }
}
