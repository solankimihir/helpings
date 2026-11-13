import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/reminders.dart';
import '../state/app_state.dart';
import 'meal_sheet.dart';
import 'shell.dart';

/// Keeps scheduled meal reminders in step with the data, and opens Add
/// Meal for the right type when a reminder is tapped.
///
/// Reminders are rescheduled whenever meals, types or the setting change
/// (logging lunch drops today's lunch reminder) and when the app returns to
/// the foreground (so the 7-day window keeps rolling forward).
class ReminderSync extends ConsumerStatefulWidget {
  const ReminderSync({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ReminderSync> createState() => _ReminderSyncState();
}

class _ReminderSyncState extends ConsumerState<ReminderSync>
    with WidgetsBindingObserver {
  /// What was last handed to the scheduler, to skip no-op reschedules.
  List<ReminderSlot>? _scheduled;

  /// Read once: `ref` can't be used in [dispose].
  late final ReminderScheduler _scheduler = ref.read(reminderSchedulerProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduler.onTap = _open;
    _start();
  }

  Future<void> _start() async {
    try {
      final data = await ref.read(appDataProvider.future);
      await _sync(data);
      // Only ask the plugin about launches once reminders exist, so a
      // device that never turned them on never touches it.
      if (!data.remindersOn) return;
      final launched = await _scheduler.launchTypeId();
      if (launched != null) _open(launched);
    } catch (e) {
      debugPrint('Reminder setup failed: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scheduler.onTap = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final data = ref.read(appDataProvider).value;
    if (state == AppLifecycleState.resumed && data != null) _sync(data);
  }

  Future<void> _sync(AppData data) async {
    final slots = data.remindersOn
        ? reminderSlots(data, DateTime.now())
        : const <ReminderSlot>[];
    // Nothing scheduled and nothing to schedule: leave the plugin alone.
    if (_scheduled == null && slots.isEmpty && !data.remindersOn) {
      _scheduled = slots;
      return;
    }
    if (listEquals(_scheduled, slots)) return;
    _scheduled = slots;
    try {
      await _scheduler.replaceAll(slots);
    } catch (e) {
      debugPrint('Scheduling reminders failed: $e');
    }
  }

  void _open(String typeId) {
    if (!mounted) return;
    ref.read(currentTabProvider.notifier).select(AppTab.home);
    showMealSheet(context, typeId: typeId);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appDataProvider, (_, next) {
      final data = next.value;
      if (data != null) _sync(data);
    });
    return widget.child;
  }
}
