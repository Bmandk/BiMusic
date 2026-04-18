import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/update_info.dart';
import '../../providers/update_provider.dart';
import '../../services/update_installer.dart' show canSelfUpdateProvider;

class UpdateAvailableDialog extends ConsumerStatefulWidget {
  const UpdateAvailableDialog({super.key, required this.info});

  final UpdateInfo info;

  @override
  ConsumerState<UpdateAvailableDialog> createState() =>
      _UpdateAvailableDialogState();
}

class _UpdateAvailableDialogState extends ConsumerState<UpdateAvailableDialog> {
  bool _isPopping = false;

  void _safePop() {
    if (_isPopping || !mounted) return;
    _isPopping = true;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UpdateState>(updateProvider, (_, next) {
      if (next is UpdateInstalled) _safePop();
    });

    final state = ref.watch(updateProvider);

    return AlertDialog(
      title: const Text('Update Available'),
      content: _buildContent(context, state),
      actions: _buildActions(context, state),
    );
  }

  Widget _buildContent(BuildContext context, UpdateState state) {
    if (state is UpdateDownloading) {
      return SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Downloading BiMusic ${widget.info.latestVersion}…',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: state.progress),
            const SizedBox(height: 8),
            Text(
              '${(state.progress * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    if (state is UpdateError) {
      return SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 8),
            Text(
              state.message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      );
    }

    // UpdateAvailable (default)
    final notes = widget.info.releaseNotes;
    final clippedNotes =
        notes.length > 2000 ? '${notes.substring(0, 2000)}…' : notes;

    return SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BiMusic ${widget.info.latestVersion} is available.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          Text(
            'You have ${widget.info.currentVersion}.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (clippedNotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'What\'s new',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: SelectableText(
                  clippedNotes,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context, UpdateState state) {
    if (state is UpdateDownloading) {
      return [
        TextButton(
          onPressed: () {
            ref.read(updateProvider.notifier).cancelDownload();
          },
          child: const Text('Cancel'),
        ),
      ];
    }

    if (state is UpdateError) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Dismiss'),
        ),
        TextButton(
          onPressed: () async {
            final uri = Uri.tryParse(widget.info.releaseUrl);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Open Release Page'),
        ),
      ];
    }

    final canSelfUpdate = ref.watch(canSelfUpdateProvider);

    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Later'),
      ),
      FilledButton(
        onPressed: () async {
          if (canSelfUpdate) {
            await ref.read(updateProvider.notifier).installNow();
          } else {
            final uri = Uri.tryParse(widget.info.releaseUrl);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
            if (context.mounted) Navigator.of(context).pop();
          }
        },
        child: const Text('Install'),
      ),
    ];
  }
}
