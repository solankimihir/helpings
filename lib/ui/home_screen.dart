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

/// Which day Home shows, as days before today (0 = today). Shared with the
/// Add button so a meal added while looking at a past day lands on that day.
final homeDayProvider = NotifierProvider<HomeDay, int>(HomeDay.new);

class HomeDay extends Notifier<int> {
  @override
  int build() => 0;
  void show(int daysAgo) => state = daysAgo;
}

/// The [dayKey] Home is showing.
String homeDayKey(WidgetRef ref) => shiftKey(-ref.read(homeDayProvider));

/// One page per day, today first; swipe right for earlier days. Tap the date
/// to jump to any day.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final PageController _pages = PageController(
    initialPage: ref.read(homeDayProvider),
  );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Today back to [firstPickableDate], inclusive.
  int get _pageCount => daysAgo(dayKey(firstPickableDate)) + 1;

  void _goTo(int daysAgo) {
    if (!_pages.hasClients) return;
    final from = _pages.page?.round() ?? 0;
    if ((daysAgo - from).abs() <= 3) {
      _pages.animateToPage(
        daysAgo,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pages.jumpToPage(daysAgo);
    }
  }

  Future<void> _pick(String current) async {
    final picked = await pickDate(context, current, last: DateTime.now());
    if (picked == null) return;
    final ago = daysAgo(picked);
    if (ago >= 0) _goTo(ago);
  }

  @override
  Widget build(BuildContext context) {
    // Follow outside changes to the day (e.g. Trends → "Open day"); swipes
    // set the provider themselves, so those are already on that page.
    ref.listen(homeDayProvider, (_, day) {
      if (_pages.hasClients && _pages.page?.round() != day) {
        _pages.jumpToPage(day);
      }
    });
    final c = context.c;
    final offset = ref.watch(homeDayProvider);
    final key = shiftKey(-offset);
    final date = parseKey(key);
    final overlineText = switch (offset) {
      0 => 'TODAY',
      1 => 'YESTERDAY',
      _ when date.year != DateTime.now().year => '${date.year}',
      _ => '$offset DAYS AGO',
    };

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Choose a day',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _pick(key),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            overlineText,
                            style: overline(context, spacing: .14),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              // Long dates ("Wednesday, September 30")
                              // shrink to stay on one line rather than wrap.
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    longDate(date),
                                    maxLines: 1,
                                    style: serif(
                                      34,
                                      color: c.ink,
                                      height: 1.08,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.expand_more_rounded,
                                size: 22,
                                color: c.inkA(.35),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (offset > 0) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Pill(
                      label: 'Today',
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 7,
                      ),
                      onTap: () => _goTo(0),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              // Page 0 (today) is rightmost: swiping right goes back a day.
              reverse: true,
              itemCount: _pageCount,
              onPageChanged: ref.read(homeDayProvider.notifier).show,
              itemBuilder: (context, i) => _DayView(dateKey: shiftKey(-i)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayView extends ConsumerWidget {
  const _DayView({required this.dateKey});
  final String dateKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).requireValue;
    final c = context.c;
    final isToday = dateKey == todayKey();
    final meals = data.meals.where((m) => m.date == dateKey).toList();

    var totals = MealTotals.zero;
    for (final m in meals) {
      totals = totals + m.totals;
    }

    final calNote = meals.isEmpty
        ? 'nothing logged'
        : totals.missing > 0
        ? 'recorded · ${plural(totals.missing, 'item')} without calories'
        : isToday
        ? 'complete for today'
        : 'complete for the day';

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, shellBottomInset(context)),
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              child: Column(
                children: [
                  Text(
                    isToday ? 'Nothing logged yet' : 'Nothing logged',
                    style: serif(22, color: c.ink),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isToday
                        ? 'Add your first meal of the day — it takes about ten seconds.'
                        : 'Tap + Add Meal to log something for this day.',
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
            // Big totals on narrow phones shrink rather than overflow.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
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
