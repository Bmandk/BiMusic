import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/auth_provider.dart';
import 'ui/screens/album_detail_screen.dart';
import 'ui/screens/artist_detail_screen.dart';
import 'ui/screens/downloads_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/library_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/playlist_detail_screen.dart';
import 'ui/screens/playlists_screen.dart';
import 'ui/screens/search_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/widgets/adaptive_scaffold.dart';

// ---------------------------------------------------------------------------
// Refresh notifier — bridges Riverpod auth state to GoRouter's listenable.
// ---------------------------------------------------------------------------

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen<AuthState>(
      authNotifierProvider,
      (_, __) => notifyListeners(),
    );
  }

  final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final authState = _ref.read(authNotifierProvider);

    // Don't redirect while startup validation is in progress.
    if (authState is AuthStateLoading) return null;

    final isAuthenticated = authState is AuthStateAuthenticated;
    final isLoginRoute = state.matchedLocation == '/login';

    if (!isAuthenticated && !isLoginRoute) return '/login';
    if (isAuthenticated && isLoginRoute) return '/home';
    return null;
  }
}

// ---------------------------------------------------------------------------
// Router provider
// ---------------------------------------------------------------------------

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);

  final router = GoRouter(
    initialLocation: '/login',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AdaptiveScaffold(
          navigationShell: navigationShell,
          child: navigationShell,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) => const LibraryScreen(),
                routes: [
                  GoRoute(
                    path: 'artist/:id',
                    builder: (context, state) => ArtistDetailScreen(
                      id: state.pathParameters['id']!,
                    ),
                  ),
                  GoRoute(
                    path: 'album/:id',
                    builder: (context, state) => AlbumDetailScreen(
                      id: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/playlists',
                builder: (context, state) => const PlaylistsScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => PlaylistDetailScreen(
                      id: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/downloads',
                builder: (context, state) => const DownloadsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  ref.onDispose(notifier.dispose);
  return router;
});
