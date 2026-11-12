import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/format.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'shell.dart';
import 'widgets/common.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).requireValue;
    final notifier = ref.read(appDataProvider.notifier);
    final c = context.c;

    Widget row({
      required String title,
      required String subtitle,
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
                Text(subtitle, style: sans(12.5, color: c.inkA(.45))),
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
                shellBottomInset(context) - 60,
              ),
              children: [
                AppCard(
                  radius: 20,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      row(
                        title: 'Default unit',
                        subtitle: 'Pre-filled for new food items',
                        trailing: SizedBox(
                          width: 112,
                          child: UnitPicker(
                            value: data.defaultUnit,
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
                const SizedBox(height: 16),
                AppCard(
                  radius: 20,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      action('Restore default food items', c.link, () async {
                        final added = await notifier.restoreDefaultItems();
                        if (!context.mounted) return;
                        toast(
                          context,
                          added == 0
                              ? 'All default food items are already here.'
                              : 'Added ${plural(added, 'food item')}.',
                        );
                      }),
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
                      }, divider: true),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 20, 6, 0),
                  child: Text(
                    'Helpings · ${plural(data.items.length, 'food item')} · '
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
}
