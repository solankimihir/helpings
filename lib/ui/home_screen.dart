import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/format.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'meal_detail_screen.dart';
import 'shell.dart';
import 'widgets/common.dart';
import 'widgets/meal_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).requireValue;
    final c = context.c;
    final today = todayKey();
    final meals = data.meals.where((m) => m.date == today).toList();

    var totals = MealTotals.zero;
    for (final m in meals) {
      totals = totals + m.totals;
    }

    final calNote = meals.isEmpty
        ? 'nothing logged'
        : totals.missing > 0
        ? 'recorded · ${plural(totals.missing, 'item')} without calories'
        : 'complete for today';

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TODAY', style: overline(context, spacing: .14)),
                const SizedBox(height: 4),
                Text(
                  longDate(DateTime.now()),
                  style: serif(34, color: c.ink, height: 1.08),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                shellBottomInset(context),
              ),
              children: [
                _SummaryCard(
                  calories: totals.sum,
                  calNote: calNote,
                  mealCount: meals.length,
                  itemCount: totals.count,
                ),
                if (meals.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: DashedBox(
                      radius: 22,
                      fill: c.surface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 30,
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Nothing logged yet',
                            style: serif(22, color: c.ink),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Add your first meal of the day — it takes about ten seconds.',
                            textAlign: TextAlign.center,
                            style: sans(13.5, color: c.inkA(.5), height: 1.45),
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final m in meals)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: MealCard(
                      meal: m,
                      data: data,
                      onTap: () => openMealDetail(context, m.id),
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.calories,
    required this.calNote,
    required this.mealCount,
    required this.itemCount,
  });

  final double calories;
  final String calNote;
  final int mealCount;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget stat(String label, String value, String? unit, String note) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: overline(context)),
            const SizedBox(height: 3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: sans(
                    32,
                    weight: FontWeight.w700,
                    color: c.ink,
                    letterSpacing: -.64,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 5),
                  Text(unit, style: sans(13, color: c.inkA(.5))),
                ],
              ],
            ),
            const SizedBox(height: 1),
            Text(note, style: sans(11.5, color: c.inkA(.45))),
          ],
        );

    return AppCard(
      raised: true,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 14,
              child: stat(
                'Calories',
                calories > 0 ? fmtN(calories) : '0',
                'kcal',
                calNote,
              ),
            ),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              color: c.inkA(.08),
            ),
            Expanded(
              flex: 10,
              child: stat(
                'Meals',
                '$mealCount',
                null,
                plural(itemCount, 'item'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
