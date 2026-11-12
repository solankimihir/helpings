import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/format.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'meal_sheet.dart';
import 'widgets/common.dart';

Future<void> openMealDetail(BuildContext context, String mealId) =>
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => MealDetailScreen(mealId: mealId)));

class MealDetailScreen extends ConsumerStatefulWidget {
  const MealDetailScreen({super.key, required this.mealId});
  final String mealId;

  @override
  ConsumerState<MealDetailScreen> createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends ConsumerState<MealDetailScreen> {
  bool _confirmDelete = false;

  Future<void> _delete() async {
    if (!_confirmDelete) {
      setState(() => _confirmDelete = true);
      return;
    }
    final nav = Navigator.of(context);
    await ref.read(appDataProvider.notifier).deleteMeal(widget.mealId);
    if (mounted) nav.pop();
  }

  void _edit(Meal meal) {
    setState(() => _confirmDelete = false);
    showMealSheet(context, editing: meal);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider).value;
    final meal = data?.mealById(widget.mealId);
    final c = context.c;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: meal == null || data == null
            ? const SizedBox.shrink()
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                          label: 'Log again',
                          style: PillStyle.white,
                          onTap: () {
                            setState(() => _confirmDelete = false);
                            showMealSheet(context, template: meal);
                          },
                        ),
                        const SizedBox(width: 8),
                        Pill(
                          label: 'Edit',
                          style: PillStyle.white,
                          onTap: () => _edit(meal),
                        ),
                        const SizedBox(width: 8),
                        Pill(
                          label: _confirmDelete ? 'Confirm delete' : 'Delete',
                          style: _confirmDelete
                              ? PillStyle.dangerSolid
                              : PillStyle.danger,
                          onTap: _delete,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _DetailBody(
                      meal: meal,
                      data: data,
                      onAddItem: () => _edit(meal),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.meal,
    required this.data,
    required this.onAddItem,
  });

  final Meal meal;
  final AppData data;
  final VoidCallback onAddItem;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = meal.totals;
    final hasItems = meal.entries.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Text(data.typeName(meal), style: serif(38, color: c.ink)),
        const SizedBox(height: 2),
        Text(
          '${longDate(parseKey(meal.date))} · ${fmtTime(meal.time)}',
          style: sans(14, color: c.inkA(.5)),
        ),
        const SizedBox(height: 20),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          child: Column(
            children: [
              for (final e in meal.entries)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.inkA(.06))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data.displayName(e),
                              style: sans(
                                16,
                                weight: FontWeight.w500,
                                color: c.ink,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              qtyLabel(e.qty, e.unit),
                              style: sans(12.5, color: c.inkA(.45)),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        e.calories == null
                            ? 'Not recorded'
                            : '${fmtN(e.calories)} kcal',
                        style: sans(
                          14,
                          color: e.calories == null ? c.inkA(.35) : c.inkA(.7),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'TOTAL',
                        style: sans(
                          13,
                          weight: FontWeight.w500,
                          color: c.inkA(.45),
                          letterSpacing: .78,
                        ),
                      ),
                    ),
                    Text(
                      !hasItems
                          ? '—'
                          : t.complete
                          ? '${fmtN(t.sum)} kcal'
                          : '${fmtN(t.sum)} kcal recorded',
                      style: sans(
                        17,
                        weight: FontWeight.w700,
                        color: t.complete ? c.ink : c.amberStrong,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!t.complete && hasItems) ...[
          const SizedBox(height: 12),
          InfoBanner.warn(
            '${t.missing == 1 ? '1 item has' : '${t.missing} items have'} '
            'no calorie value, so this total is incomplete.',
          ),
        ],
        if (meal.notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionLabel('Notes', padding: EdgeInsets.only(bottom: 6)),
          AppCard(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                meal.notes,
                style: sans(14.5, color: c.ink, height: 1.5),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        DashedBox(
          onTap: onAddItem,
          child: Text(
            '+ Add meal item',
            textAlign: TextAlign.center,
            style: sans(14.5, weight: FontWeight.w500, color: c.greenText),
          ),
        ),
      ],
    );
  }
}
