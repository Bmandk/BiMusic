import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Maps the 5 visible mobile tab indices to shell branch indices.
/// Shell branches: 0=Home, 1=Library, 2=Search, 3=Playlists, 4=Downloads, 5=Settings
/// Mobile tabs:    0=Home, 1=Library, 2=Search, 3=Playlists, 4=Settings
const List<int> _mobileToBranchIndex = [0, 1, 2, 3, 5];

class MobileLayout extends StatelessWidget {
  const MobileLayout({
    super.key,
    required this.navigationShell,
    required this.child,
  });

  final StatefulNavigationShell navigationShell;
  final Widget child;

  int get _selectedTabIndex {
    final branchIndex = navigationShell.currentIndex;
    final tabIndex = _mobileToBranchIndex.indexOf(branchIndex);
    return tabIndex < 0 ? 0 : tabIndex;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: child),
          Container(
            height: 60,
            color: theme.colorScheme.surface,
            child: const Center(child: Text('Mini Player')),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (tabIndex) {
          navigationShell.goBranch(_mobileToBranchIndex[tabIndex]);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.queue_music_outlined),
            selectedIcon: Icon(Icons.queue_music),
            label: 'Playlists',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
