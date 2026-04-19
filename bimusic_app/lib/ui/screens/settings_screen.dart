import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../providers/auth_provider.dart';
import '../../providers/backend_url_provider.dart';
import '../../providers/bitrate_preference_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/launch_at_startup_provider.dart';
import '../../providers/minimize_to_tray_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/update_provider.dart';
import '../../services/api_client.dart';
import '../../utils/platform.dart';
import '../dialogs/update_available_dialog.dart';

// ---------------------------------------------------------------------------
// Async providers
// ---------------------------------------------------------------------------

final _packageInfoProvider = FutureProvider<PackageInfo>(
  (_) => PackageInfo.fromPlatform(),
);

final _backendHealthProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dio = ref.read(apiClientProvider);
  final resp = await dio.get<Map<String, dynamic>>('/api/health');
  return resp.data!;
});

final _adminLogsProvider = FutureProvider<List<String>>((ref) async {
  final dio = ref.read(apiClientProvider);
  final resp = await dio.get<Map<String, dynamic>>('/api/admin/logs');
  final lines = (resp.data!['lines'] as List<dynamic>).cast<String>();
  return lines;
});

// ---------------------------------------------------------------------------
// Settings screen
// ---------------------------------------------------------------------------

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    if (authState is! AuthStateAuthenticated) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final user = authState.tokens.user;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // ----------------------------------------------------------------
          // Account
          // ----------------------------------------------------------------
          const _SectionHeader(title: 'Account'),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              child: Text(
                user.username.isNotEmpty
                    ? user.username[0].toUpperCase()
                    : '?',
                style: TextStyle(color: colorScheme.onPrimaryContainer),
              ),
            ),
            title: Text(user.username),
            subtitle: user.isAdmin ? const Text('Administrator') : null,
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign Out'),
            onTap: () => _confirmLogout(context, ref),
          ),
          const Divider(),

          // ----------------------------------------------------------------
          // Playback
          // ----------------------------------------------------------------
          const _SectionHeader(title: 'Playback'),
          _BitratePreferenceTile(),
          ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: const Text('Crossfade'),
            subtitle: const Text('Coming soon'),
            enabled: false,
            trailing: Text(
              '0 s',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colorScheme.outline),
            ),
          ),
          const Divider(),

          // ----------------------------------------------------------------
          // Desktop (Windows / Linux only)
          // ----------------------------------------------------------------
          if (isDesktop) ...[
            const _SectionHeader(title: 'Desktop'),
            _DesktopSection(),
            const Divider(),
          ],

          // ----------------------------------------------------------------
          // Storage (not shown on web)
          // ----------------------------------------------------------------
          if (!kIsWeb) ...[
            const _SectionHeader(title: 'Offline Downloads'),
            _StorageSection(),
            const Divider(),
          ],

          // ----------------------------------------------------------------
          // Debug (admin only)
          // ----------------------------------------------------------------
          if (user.isAdmin) ...[
            const _SectionHeader(title: 'Debug'),
            _BackendHealthTile(),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('View Logs'),
              subtitle: const Text('Last 200 lines'),
              onTap: () => _showLogs(context, ref),
            ),
            const Divider(),
          ],

          // ----------------------------------------------------------------
          // About
          // ----------------------------------------------------------------
          const _SectionHeader(title: 'About'),
          _AboutSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
          'Are you sure? Offline downloads on this device will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(playerNotifierProvider.notifier).pause();
      await ref.read(authNotifierProvider.notifier).logout();
    }
  }

  Future<void> _showLogs(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => const _LogViewerDialog(),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit backend URL dialog
// ---------------------------------------------------------------------------

class _EditBackendUrlDialog extends ConsumerStatefulWidget {
  const _EditBackendUrlDialog({required this.current});

  final String current;

  @override
  ConsumerState<_EditBackendUrlDialog> createState() =>
      _EditBackendUrlDialogState();
}

class _EditBackendUrlDialogState extends ConsumerState<_EditBackendUrlDialog> {
  late final TextEditingController _controller;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Please enter a URL.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final currentUrl = ref.read(backendUrlProvider).valueOrNull;
      final urlChanged = text != currentUrl;
      await ref.read(backendUrlProvider.notifier).setUrl(text);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (urlChanged) {
        final player = ref.read(playerNotifierProvider.notifier);
        final auth = ref.read(authNotifierProvider.notifier);
        await player.pause();
        await auth.logout();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Backend URL'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'http://192.168.1.10:3000',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            onSubmitted: (_) => _isLoading ? null : _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _save,
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section header helper
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bitrate preference tile
// ---------------------------------------------------------------------------

class _BitratePreferenceTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pref = ref.watch(bitratePreferenceProvider);

    return ListTile(
      leading: const Icon(Icons.high_quality_outlined),
      title: const Text('Streaming Quality'),
      subtitle: Text(_prefLabel(pref)),
      onTap: () => _showPicker(context, ref, pref),
    );
  }

  String _prefLabel(BitratePreference pref) {
    switch (pref) {
      case BitratePreference.auto:
        return 'Automatic (320 kbps on WiFi, 128 kbps on mobile)';
      case BitratePreference.alwaysLow:
        return 'Always Low (128 kbps)';
      case BitratePreference.alwaysHigh:
        return 'Always High (320 kbps)';
    }
  }

  Future<void> _showPicker(
    BuildContext context,
    WidgetRef ref,
    BitratePreference current,
  ) async {
    final selected = await showDialog<BitratePreference>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Streaming Quality'),
        children: BitratePreference.values
            .map(
              (p) => ListTile(
                leading: current == p
                    ? const Icon(Icons.radio_button_checked)
                    : const Icon(Icons.radio_button_unchecked),
                title: Text(_prefLabel(p)),
                onTap: () => Navigator.of(ctx).pop(p),
              ),
            )
            .toList(),
      ),
    );
    if (selected != null) {
      await ref
          .read(bitratePreferenceProvider.notifier)
          .setPreference(selected);
    }
  }
}

// ---------------------------------------------------------------------------
// Desktop section
// ---------------------------------------------------------------------------

class _DesktopSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final launchAtStartup = ref.watch(launchAtStartupProvider);
    final minimizeToTray = ref.watch(minimizeToTrayProvider);

    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.rocket_launch_outlined),
          title: const Text('Launch at Startup'),
          subtitle: const Text('Start BiMusic when you log in'),
          value: launchAtStartup,
          onChanged: (value) =>
              ref.read(launchAtStartupProvider.notifier).setEnabled(value),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.minimize),
          title: const Text('Minimize to Tray'),
          subtitle: const Text('Hide to system tray instead of closing'),
          value: minimizeToTray,
          onChanged: (value) =>
              ref.read(minimizeToTrayProvider.notifier).setEnabled(value),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Storage section
// ---------------------------------------------------------------------------

class _StorageSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageUsageProvider);

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: const Text('Offline Music'),
          trailing: Text(
            storage.formattedSize,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          subtitle: Text('${storage.trackCount} track${storage.trackCount == 1 ? '' : 's'}'),
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('Clear All Downloads'),
          textColor: Theme.of(context).colorScheme.error,
          iconColor: Theme.of(context).colorScheme.error,
          onTap: () => _confirmClearAll(context, ref),
        ),
      ],
    );
  }

  Future<void> _confirmClearAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Downloads'),
        content: const Text(
          'Remove all offline downloads from this device? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(downloadProvider.notifier).clearAllDownloads();
    }
  }
}

// ---------------------------------------------------------------------------
// Backend health tile
// ---------------------------------------------------------------------------

class _BackendHealthTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(_backendHealthProvider);

    return health.when(
      data: (data) {
        final version = data['version'] as String? ?? 'unknown';
        return ListTile(
          leading: Icon(
            Icons.check_circle_outline,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text('Backend'),
          subtitle: Text('v$version — healthy'),
        );
      },
      loading: () => const ListTile(
        leading: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('Backend'),
        subtitle: Text('Checking…'),
      ),
      error: (_, __) => ListTile(
        leading: Icon(
          Icons.error_outline,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const Text('Backend'),
        subtitle: const Text('Unreachable'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// About section
// ---------------------------------------------------------------------------

class _AboutSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pkgInfo = ref.watch(_packageInfoProvider);
    final url = ref.watch(backendUrlProvider).valueOrNull ?? '';

    final appVersion = pkgInfo.maybeWhen(
      data: (info) => '${info.version}+${info.buildNumber}',
      orElse: () => '…',
    );

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('App Version'),
          trailing: Text(
            appVersion,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: const Text('Backend URL'),
          subtitle: Text(url.isEmpty ? '—' : url),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _showEditUrlDialog(context, ref, url),
        ),
        Consumer(
          builder: (context, ref, _) {
            final updateState = ref.watch(updateProvider);
            final busy = updateState is UpdateChecking ||
                updateState is UpdateDownloading;
            return ListTile(
              leading: const Icon(Icons.system_update_outlined),
              title: const Text('Check for Updates'),
              trailing: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: busy
                  ? null
                  : () async {
                      await ref
                          .read(updateProvider.notifier)
                          .checkManual();
                      final s = ref.read(updateProvider);
                      if (!context.mounted) return;
                      switch (s) {
                        case UpdateUpToDate():
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('You are up to date.')),
                          );
                        case UpdateError(message: final m):
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Update check failed: $m')),
                          );
                        case UpdateAvailable(info: final i):
                          showDialog<void>(
                            context: context,
                            builder: (_) => UpdateAvailableDialog(info: i),
                          );
                        default:
                          break;
                      }
                    },
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.gavel_outlined),
          title: const Text('Open Source Licenses'),
          onTap: () {
            final pkgData = pkgInfo.valueOrNull;
            showLicensePage(
              context: context,
              applicationName: pkgData?.appName ?? 'BiMusic',
              applicationVersion: pkgData != null
                  ? '${pkgData.version}+${pkgData.buildNumber}'
                  : null,
            );
          },
        ),
      ],
    );
  }

  Future<void> _showEditUrlDialog(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _EditBackendUrlDialog(current: current),
    );
  }
}

// ---------------------------------------------------------------------------
// Log viewer dialog
// ---------------------------------------------------------------------------

class _LogViewerDialog extends ConsumerWidget {
  const _LogViewerDialog();

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final logs = widgetRef.watch(_adminLogsProvider);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Server Logs',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: logs.when(
                data: (lines) => _LogList(lines: lines),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Failed to load logs: $e',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () =>
                        widgetRef.invalidate(_adminLogsProvider),
                    child: const Text('Refresh'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogList extends StatefulWidget {
  const _LogList({required this.lines});

  final List<String> lines;

  @override
  State<_LogList> createState() => _LogListState();
}

class _LogListState extends State<_LogList> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController
            .jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: widget.lines.length,
      itemBuilder: (_, i) => Text(
        widget.lines[i],
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
    );
  }
}
