import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/format.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'meal_detail_screen.dart';
import 'shell.dart';
import 'widgets/common.dart';

class _DayGroup {
  _DayGroup(this.date);
  final String date;
  final meals = <Meal>[];
  var totals = MealTotals.zero;
}

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  /// Meal type id; null = All.
  String? _filter;

  List<_DayGroup> _groups(AppData data) {
    final groups = <_DayGroup>[];
    // Newest day first; within a day, earliest meal first.
    for (final m in data.meals.reversed) {
      if (_filter != null && m.typeId != _filter) continue;
      if (groups.isEmpty || groups.last.date != m.date) {
        groups.add(_DayGroup(m.date));
      }
      final g = groups.last;
      g.meals.insert(0, m);
      g.totals = g.totals + m.totals;
    }
    return groups;
  }

  Future<bool> _confirmDelete(Meal m, String typeName) => confirm(
    context,
    title: 'Delete ${typeName.toLowerCase()}?',
    message:
        '$typeName on ${dayGroupLabel(m.date)} at ${fmtTime(m.time)} '
        'will be removed. This can’t be undone.',
    action: 'Delete',
  );

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider).requireValue;
    final c = context.c;
    // Visible types, plus hidden ones that past meals still use.
    final used = {for (final m in data.meals) m.typeId};
    final filterTypes = [
      for (final t in data.mealTypes)
        if (t.active || used.contains(t.id)) t,
    ];
    // A filter on a type that was since deleted would show nothing.
    if (_filter != null && data.typeById(_filter!) == null) _filter = null;
    final groups = _groups(data);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 6),
            child: Text('History', style: serif(32, color: c.ink)),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              children: [
                for (final t in <MealType?>[null, ...filterTypes])
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: AppChip(
                      label: t?.name ?? 'All',
                      selected: t?.id == _filter,
                      onTap: () => setState(() => _filter = t?.id),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: groups.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(26, 40, 26, 0),
                    child: Text(
                      data.meals.isEmpty
                          ? 'Meals you log will show up here.'
                          : 'No meals match this filter.',
                      textAlign: TextAlign.center,
                      style: sans(14, color: c.inkA(.45)),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      shellBottomInset(context),
                    ),
                    itemCount: groups.length,
                    itemBuilder: (context, i) => _GroupView(
                      group: groups[i],
                      typeName: data.typeName,
                      onOpen: (m) => openMealDetail(context, m.id),
                      confirmDelete: (m) => _confirmDelete(m, data.typeName(m)),
                      onDelete: (m) =>
                          ref.read(appDataProvider.notifier).deleteMeal(m.id),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _GroupView extends StatelessWidget {
  const _GroupView({
    required this.group,
    required this.typeName,
    required this.onOpen,
    required this.confirmDelete,
    required this.onDelete,
  });

  final _DayGroup group;
  final String Function(Meal) typeName;
  final ValueChanged<Meal> onOpen;
  final Future<bool> Function(Meal) confirmDelete;
  final ValueChanged<Meal> onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = group.totals;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              children: [
                Text(
                  dayGroupLabel(group.date),
                  style: sans(15, weight: FontWeight.w700, color: c.ink),
                ),
                const SizedBox(width: 8),
                Expanded(child: Container(height: 1, color: c.inkA(.1))),
                const SizedBox(width: 8),
                Text(
                  t.missing > 0
                      ? '${fmtN(t.sum)}+ kcal'
                      : '${fmtN(t.sum)} kcal',
                  style: sans(12, color: c.inkA(.45)),
                ),
              ],
            ),
          ),
          AppCard(
            radius: 20,
            child: Column(
              children: [
                for (final (i, m) in group.meals.indexed)
                  Dismissible(
                    key: ValueKey(m.id),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) => confirmDelete(m),
                    onDismissed: (_) => onDelete(m),
                    background: Container(
                      color: c.danger,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: Text(
                        'Delete',
                        style: sans(
                          14,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    child: _HistoryRow(
                      meal: m,
                      typeName: typeName(m),
                      showDivider: i > 0,
                      onTap: () => onOpen(m),
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

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.meal,
    required this.typeName,
    required this.showDivider,
    required this.onTap,
  });

  final Meal meal;
  final String typeName;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = meal.totals;
    final summary =
        plural(meal.entries.length, 'item') +
        (meal.notes.isNotEmpty ? ' · note' : '');
    return Material(
      color: c.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: showDivider
                ? Border(top: BorderSide(color: c.inkA(.06)))
                : null,
          ),
          child: Row(
            children: [
              MealBadge(typeName, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: typeName,
                        children: [
                          TextSpan(
                            text: ' — ${fmtTime(meal.time)}',
                            style: sans(15, color: c.inkA(.4)),
                          ),
                        ],
                      ),
                      style: sans(15, weight: FontWeight.w500, color: c.ink),
                    ),
                    const SizedBox(height: 1),
                    Text(summary, style: sans(12.5, color: c.inkA(.45))),
                  ],
                ),
              ),
              Text(
                calLabel(t),
                style: sans(
                  12.5,
                  color: t.complete || t.count == 0 ? c.inkA(.4) : c.amberText,
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.chevron_right_rounded, size: 18, color: c.inkA(.25)),
            ],
          ),
        ),
      ),
    );
  }
}
