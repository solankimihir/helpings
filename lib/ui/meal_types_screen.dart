import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/format.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'meal_type_sheet.dart';
import 'widgets/common.dart';

Future<void> openMealTypes(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const MealTypesScreen()));

/// Settings → Meal types: add, edit, drag to reorder.
class MealTypesScreen extends ConsumerWidget {
  const MealTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).requireValue;
    final types = data.mealTypes;
    final c = context.c;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: softShadow(context),
                    ),
                    child: Tap(
                      onTap: () => Navigator.of(context).maybePop(),
                      color: c.surface,
                      semanticLabel: 'Back',
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: Icon(
                          Icons.chevron_left_rounded,
                          size: 24,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Pill(
                    label: '+ Add',
                    style: PillStyle.primary,
                    onTap: () => showMealTypeSheet(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 2),
              child: Text('Meal types', style: serif(32, color: c.ink)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
              child: Text(
                'Tap to edit. Drag to change the order of the chips.',
                style: sans(13, color: c.inkA(.5)),
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                buildDefaultDragHandles: false,
                itemCount: types.length,
                onReorderItem: (from, to) {
                  final ids = [for (final t in types) t.id];
                  ids.insert(to, ids.removeAt(from));
                  ref.read(appDataProvider.notifier).reorderMealTypes(ids);
                },
                itemBuilder: (context, i) => Padding(
                  key: ValueKey(types[i].id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _TypeRow(type: types[i], index: i),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.type, required this.index});
  final MealType type;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final start = type.startMinute;
    final details = [
      if (start != null) 'from ${fmtTime(minuteKey(start))}',
      if (type.remindMinute case final r?) 'reminds ${fmtTime(minuteKey(r))}',
      if (!type.active) 'hidden',
    ].join(' · ');
    return AppCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      onTap: () => showMealTypeSheet(context, editing: type),
      child: Row(
        children: [
          Opacity(
            opacity: type.active ? 1 : .45,
            child: MealBadge(type.name, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type.name,
                  style: sans(
                    15.5,
                    weight: FontWeight.w600,
                    color: type.active ? c.ink : c.inkA(.5),
                  ),
                ),
                if (details.isNotEmpty)
                  Text(details, style: sans(12.5, color: c.inkA(.45))),
              ],
            ),
          ),
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                Icons.drag_handle_rounded,
                size: 22,
                color: c.inkA(.35),
                semanticLabel: 'Reorder ${type.name}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
