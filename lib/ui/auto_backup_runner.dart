import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';

/// Runs the daily automatic backup on the first open of each day: when the
/// app starts, and when it comes back to the foreground (Android and iOS
/// often keep the app alive overnight, so a cold start can't be relied on).
class AutoBackupRunner extends ConsumerStatefulWidget {
  const AutoBackupRunner({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AutoBackupRunner> createState() => _AutoBackupRunnerState();
}

class _AutoBackupRunnerState extends ConsumerState<AutoBackupRunner>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _run();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _run();
  }

  Future<void> _run() async {
    try {
      await ref.read(appDataProvider.future);
    } catch (_) {
      return; // The UI shows load errors.
    }
    if (!mounted) return;
    await ref.read(appDataProvider.notifier).runAutoBackupIfDue();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
