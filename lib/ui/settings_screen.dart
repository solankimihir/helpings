import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/backup.dart';
import '../data/csv_export.dart';
import '../data/database.dart';
import '../data/food_csv.dart';
import '../data/format.dart';
import '../data/reminders.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../version.dart';
import 'ai_foods_screen.dart';
import 'combos_screen.dart';
import 'meal_type_sheet.dart' show minuteKey;
import 'meal_types_screen.dart';
import 'shell.dart';
import 'units_screen.dart';
import 'widgets/common.dart';

final _backupDate = DateFormat('MMM d, y · h:mm a', 'en_US');

/// "last backup today" / "last backup November 10".
String _lastAutoLabel(String? day) {
  if (day == null) return 'no backup yet';
  final l = dayGroupLabel(day);
  return 'last backup ${day == todayKey() || l == 'Yesterday' ? l.toLowerCase() : l}';
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).requireValue;
    final notifier = ref.read(appDataProvider.notifier);
    final c = context.c;
    final auto = data.autoBackup;

    Widget row({
      required String title,
      required String subtitle,
      Color? subtitleColor,
      required Widget trailing,
      bool divider = true,
    }) => Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: divider ? Border(bottom: BorderSide(color: c.inkA(.06))) : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: sans(15, weight: FontWeight.w500, color: c.ink),
                ),
                Text(
                  subtitle,
                  style: sans(12.5, color: subtitleColor ?? c.inkA(.45)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );

    Widget action(
      String label,
      Color color,
      VoidCallback onTap, {
      bool divider = false,
    }) => Container(
      decoration: BoxDecoration(
        border: divider ? Border(top: BorderSide(color: c.inkA(.06))) : null,
      ),
      child: Tap(
        onTap: onTap,
        radius: 0,
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            label,
            style: sans(15, weight: FontWeight.w500, color: color),
          ),
        ),
      ),
    );

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 6),
            child: Text('Settings', style: serif(32, color: c.ink)),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                shellBottomInset(context),
              ),
              children: [
                AppCard(
                  radius: 20,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Appearance',
                        style: sans(15, weight: FontWeight.w500, color: c.ink),
                      ),
                      Text(
                        'System follows your device setting',
                        style: sans(12.5, color: c.inkA(.45)),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (mode, label) in const [
                            (ThemeMode.system, 'System'),
                            (ThemeMode.light, 'Light'),
                            (ThemeMode.dark, 'Dark'),
                          ])
                            AppChip(
                              label: label,
                              selected: data.themeMode == mode,
                              onTap: () => notifier.setThemeMode(mode),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SectionLabel(
                  'Meals',
                  padding: EdgeInsets.fromLTRB(6, 22, 6, 8),
                ),
                AppCard(
                  radius: 20,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      Tap(
                        onTap: () => openMealTypes(context),
                        radius: 0,
                        child: row(
                          title: 'Meal types',
                          subtitle: data.visibleTypes
                              .map((t) => t.name)
                              .join(' · '),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                plural(data.mealTypes.length, 'type'),
                                style: sans(14, color: c.inkA(.5)),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: c.inkA(.3),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Tap(
                        onTap: () => openCombos(context),
                        radius: 0,
                        child: row(
                          title: 'Combos',
                          subtitle: data.combos.isEmpty
                              ? 'Items you often eat together, added in one tap'
                              : data.combos.map((x) => x.name).join(' · '),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${data.combos.length}',
                                style: sans(14, color: c.inkA(.5)),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: c.inkA(.3),
                              ),
                            ],
                          ),
                        ),
                      ),
                      row(
                        title: 'Meal reminders',
                        subtitle: _remindersSubtitle(data),
                        trailing: Switch.adaptive(
                          value: data.remindersOn,
                          onChanged: (on) => _setReminders(context, ref, on),
                        ),
                      ),
                      row(
                        title: 'Default meal time',
                        subtitle: 'Used when adding a meal',
                        trailing: Text(
                          'Now',
                          style: sans(14, color: c.inkA(.5)),
                        ),
                      ),
                      row(
                        title: 'Calorie totals',
                        subtitle: 'Never estimated — only what you enter',
                        divider: false,
                        trailing: Text(
                          'Exact',
                          style: sans(
                            14,
                            weight: FontWeight.w500,
                            color: c.link,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionLabel(
                  'Food list',
                  padding: EdgeInsets.fromLTRB(6, 22, 6, 8),
                ),
                AppCard(
                  radius: 20,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      Tap(
                        onTap: () => openAiFoods(context),
                        radius: 0,
                        child: row(
                          title: 'Ask an AI',
                          subtitle:
                              'Build a starter food list, or fill in missing '
                              'calories',
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: c.inkA(.3),
                          ),
                        ),
                      ),
                      Tap(
                        onTap: () => openUnits(context),
                        radius: 0,
                        child: row(
                          title: 'Units',
                          subtitle: data.visibleUnits
                              .map((u) => u.name)
                              .join(' · '),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                plural(data.units.length, 'unit'),
                                style: sans(14, color: c.inkA(.5)),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: c.inkA(.3),
                              ),
                            ],
                          ),
                        ),
                      ),
                      row(
                        title: 'Default unit',
                        subtitle: 'Pre-filled for new food items',
                        trailing: SizedBox(
                          width: 112,
                          child: UnitPicker(
                            value: data.defaultUnit,
                            units: data.unitsFor(data.defaultUnit),
                            fontSize: 14,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            onChanged: (u) {
                              if (u != null) notifier.setDefaultUnit(u);
                            },
                          ),
                        ),
                      ),
                      action(
                        'Export food list (CSV)',
                        c.link,
                        () => _exportFoods(context, ref),
                      ),
                      action('Restore default food items', c.link, () async {
                        final added = await notifier.restoreDefaultItems();
                        if (!context.mounted) return;
                        toast(
                          context,
                          added == 0
                              ? 'All default food items are already here.'
                              : 'Added ${plural(added, 'food item')}.',
                        );
                      }, divider: true),
                    ],
                  ),
                ),
                const SectionLabel(
                  'Backup and export',
                  padding: EdgeInsets.fromLTRB(6, 22, 6, 8),
                ),
                AppCard(
                  radius: 20,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      row(
                        title: 'Backup',
                        subtitle: data.lastBackupAt == null
                            ? 'Save a copy of your data to a file'
                            : 'Last saved '
                                  '${_backupDate.format(data.lastBackupAt!)}',
                        trailing: Pill(
                          label: 'Save copy',
                          onTap: () async {
                            try {
                              final saved = await notifier.backup();
                              if (saved && context.mounted) {
                                toast(context, 'Backup saved.');
                              }
                            } catch (e) {
                              if (context.mounted) {
                                toast(context, "Couldn't save the backup.");
                              }
                            }
                          },
                        ),
                      ),
                      row(
                        title: 'Daily backup',
                        subtitle: switch (auto) {
                          null =>
                            'Saves to a folder you choose on the first open '
                                'each day. Keeps the last $autoBackupKeep.',
                          AutoBackupStatus(:final error?) => error,
                          AutoBackupStatus(:final folderName, :final lastDay) =>
                            '“$folderName” · ${_lastAutoLabel(lastDay)}',
                        },
                        subtitleColor: auto?.error != null ? c.danger : null,
                        trailing: Pill(
                          label: auto == null ? 'Choose folder' : 'Change',
                          onTap: () async {
                            final chose = await notifier
                                .chooseAutoBackupFolder();
                            if (!chose || !context.mounted) return;
                            final s = ref
                                .read(appDataProvider)
                                .value
                                ?.autoBackup;
                            toast(
                              context,
                              s?.error ??
                                  'Daily backup is on. Today’s is saved.',
                            );
                          },
                        ),
                      ),
                      if (auto != null)
                        action('Turn off daily backup', c.inkA(.7), () async {
                          await notifier.disableAutoBackup();
                          if (context.mounted) {
                            toast(
                              context,
                              'Daily backup is off. Saved files are kept.',
                            );
                          }
                        }),
                      action(
                        'Restore from a backup…',
                        c.link,
                        () => _restore(context, ref),
                        divider: auto != null,
                      ),
                      action(
                        'Export meals (CSV)',
                        c.link,
                        () => _exportCsv(context, ref),
                        divider: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppCard(
                  radius: 20,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      action('Delete all meals', c.danger, () async {
                        if (data.meals.isEmpty) {
                          toast(context, 'There are no meals to delete.');
                          return;
                        }
                        final ok = await confirm(
                          context,
                          title: 'Delete all meals?',
                          message:
                              'All ${plural(data.meals.length, 'meal')} will be '
                              'permanently removed from this device. Food '
                              'items are kept.',
                          action: 'Delete all',
                        );
                        if (!ok) return;
                        await notifier.deleteAllMeals();
                        if (context.mounted) {
                          toast(context, 'All meals deleted.');
                        }
                      }),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 20, 6, 0),
                  child: Text(
                    'Helpings $appVersion ($appBuild)\n'
                    '${plural(data.items.length, 'food item')} · '
                    '${plural(data.meals.length, 'meal')} stored on device',
                    style: sans(12, color: c.inkA(.4), height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final Uint8List? bytes;
    try {
      bytes = await ref.read(backupPickerProvider)();
    } catch (_) {
      if (context.mounted) toast(context, "Couldn't open that file.");
      return;
    }
    if (bytes == null || !context.mounted) return;
    if (!AppDatabase.isSqliteFile(bytes)) {
      toast(context, "This file isn't a Helpings backup.");
      return;
    }
    final data = ref.read(appDataProvider).requireValue;
    final folder = data.autoBackup?.folderName;
    final ok = await confirm(
      context,
      title: 'Restore this backup?',
      message:
          'Your ${plural(data.meals.length, 'meal')} and '
          '${plural(data.items.length, 'food item')} on this device will be '
          'replaced by the backup. '
          '${folder != null ? 'A copy of your current data will be saved to “$folder” first.' : 'This can’t be undone, so save a copy first if you might want it back.'}',
      action: 'Restore',
    );
    if (!ok) return;
    try {
      await ref.read(appDataProvider.notifier).restore(bytes);
      final now = ref.read(appDataProvider).requireValue;
      if (context.mounted) {
        toast(
          context,
          'Restored ${plural(now.meals.length, 'meal')} and '
          '${plural(now.items.length, 'food item')}.',
        );
      }
    } on BackupFormatException catch (e) {
      if (context.mounted) toast(context, e.message);
    } catch (e) {
      debugPrint('Restore failed: $e');
      if (context.mounted) toast(context, "Couldn't restore this backup.");
    }
  }

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    final data = ref.read(appDataProvider).requireValue;
    if (data.meals.isEmpty) {
      toast(context, 'There are no meals to export yet.');
      return;
    }
    try {
      final saved = await ref.read(csvSaverProvider)(
        csvFileName(DateTime.now()),
        csvBytes(mealsToCsv(data)),
      );
      if (saved && context.mounted) {
        toast(context, 'Exported ${plural(data.meals.length, 'meal')}.');
      }
    } catch (e) {
      debugPrint('CSV export failed: $e');
      if (context.mounted) toast(context, "Couldn't export your meals.");
    }
  }

  Future<void> _exportFoods(BuildContext context, WidgetRef ref) async {
    final data = ref.read(appDataProvider).requireValue;
    if (data.items.isEmpty) {
      toast(context, 'There are no foods to export yet.');
      return;
    }
    try {
      final saved = await ref.read(csvSaverProvider)(
        foodCsvFileName(DateTime.now()),
        csvBytes(foodsToCsv(data)),
      );
      if (saved && context.mounted) {
        toast(context, 'Exported ${plural(data.items.length, 'food')}.');
      }
    } catch (e) {
      debugPrint('Food CSV export failed: $e');
      if (context.mounted) toast(context, "Couldn't export your foods.");
    }
  }

  static String _remindersSubtitle(AppData data) {
    final timed = [
      for (final t in data.visibleTypes)
        if (t.remindMinute != null)
          '${t.name} ${fmtTime(minuteKey(t.remindMinute!))}',
    ];
    if (!data.remindersOn) {
      return 'A nudge if a meal isn’t logged by its time';
    }
    return timed.isEmpty
        ? 'Set a “Remind me at” time on a meal type'
        : timed.join(' · ');
  }

  Future<void> _setReminders(
    BuildContext context,
    WidgetRef ref,
    bool on,
  ) async {
    final notifier = ref.read(appDataProvider.notifier);
    if (!on) {
      await notifier.setRemindersOn(false);
      return;
    }
    final bool allowed;
    try {
      allowed = await ref.read(reminderSchedulerProvider).requestPermission();
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
      if (context.mounted) toast(context, "Couldn't turn on reminders.");
      return;
    }
    if (!allowed) {
      if (context.mounted) {
        toast(
          context,
          'Notifications are off for Helpings. Allow them in your phone’s '
          'settings, then try again.',
        );
      }
      return;
    }
    await notifier.setRemindersOn(true);
    final data = ref.read(appDataProvider).requireValue;
    if (context.mounted &&
        data.visibleTypes.every((t) => t.remindMinute == null)) {
      toast(context, 'Now set a reminder time in Meal types.');
    }
  }
}
