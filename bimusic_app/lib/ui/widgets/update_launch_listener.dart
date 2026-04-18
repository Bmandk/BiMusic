import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../providers/update_provider.dart';
import '../dialogs/update_available_dialog.dart';

/// Wraps a child widget and, once auth resolves, silently checks for updates.
/// Shows an [UpdateAvailableDialog] the first time an update is detected.
class UpdateLaunchListener extends ConsumerStatefulWidget {
  const UpdateLaunchListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateLaunchListener> createState() =>
      _UpdateLaunchListenerState();
}

class _UpdateLaunchListenerState extends ConsumerState<UpdateLaunchListener> {
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(authNotifierProvider.notifier).initialized;
      if (!mounted) return;
      ref.read(updateProvider.notifier).checkOnLaunch();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UpdateState>(updateProvider, (_, next) {
      if (next is UpdateAvailable && !_dialogShown) {
        _dialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            showDialog<void>(
              context: context,
              builder: (_) => UpdateAvailableDialog(info: next.info),
            );
          }
        });
      }
    });

    return widget.child;
  }
}
