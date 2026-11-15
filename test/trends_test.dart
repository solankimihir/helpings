import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/data/trends.dart';
import 'package:helpings/state/app_state.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

Meal _meal(String id, String date, List<(String, double?)> lines) => Meal(
  id: id,
  typeId: 'lunch',
  date: date,
  time: '12:00',
  entries: [
    for (final (i, (name, cal)) in lines.indexed)
      MealEntry(id: '$id-$i', nameSnapshot: name, calories: cal),
  ],
);

AppData _data(List<Meal> meals) =>
    AppData(items: const [], meals: meals, defaultUnit: FoodUnit.piece);

/// Thursday.
final _now = DateTime(2026, 11, 12, 9);

void main() {
  group('summarizeTrends', () {
    test('week runs Monday to Sunday, with labels across months', () {
      final s = summarizeTrends(_data([]), TrendRange.week, 0, _now);
      expect(s.label, 'Nov 9 – 15');
      expect(s.days.first.date, '2026-11-09');
      expect(s.days, hasLength(7));
      expect(
        summarizeTrends(_data([]), TrendRange.week, 1, _now).label,
        'Nov 2 – 8',
      );
      expect(
        summarizeTrends(_data([]), TrendRange.week, 2, _now).label,
        'Oct 26 – Nov 1',
      );
    });

    test('months have their real length, leap years included', () {
      final nov = summarizeTrends(_data([]), TrendRange.month, 0, _now);
      expect((nov.label, nov.days.length), ('November 2026', 30));
      final feb = summarizeTrends(
        _data([]),
        TrendRange.month,
        0,
        DateTime(2028, 2, 10),
      );
      expect((feb.label, feb.days.length), ('February 2028', 29));
      final dec = summarizeTrends(_data([]), TrendRange.month, 11, _now);
      expect(dec.label, 'December 2025');
    });

    test('totals, incomplete days, average over logged days only', () {
      final s = summarizeTrends(
        _data([
          _meal('a', '2026-11-09', [('Roti', 200), ('Dal', 180)]),
          _meal('b', '2026-11-09', [('Tea', 90)]),
          _meal('c', '2026-11-11', [('Sambar', null), ('Idli', 120)]),
          _meal('d', '2026-11-20', [('Roti', 999)]), // next week
        ]),
        TrendRange.week,
        0,
        _now,
      );
      final mon = s.days[0];
      expect((mon.calories, mon.meals, mon.incomplete), (470.0, 2, false));
      final wed = s.days[2];
      expect((wed.calories, wed.missing, wed.incomplete), (120.0, 1, true));
      expect(s.mealCount, 3);
      expect(s.loggedDays, hasLength(2));
      expect(s.averagePerLoggedDay, (470 + 120) / 2);
      expect(s.maxCalories, 470);
    });

    test('top foods: by count, ties alphabetical, at most five', () {
      final s = summarizeTrends(
        _data([
          _meal('a', '2026-11-09', [('Tea', 90), ('Roti', 100)]),
          _meal('b', '2026-11-10', [('Tea', 90), ('roti', 100)]),
          _meal('c', '2026-11-10', [
            ('Dal', 1),
            ('Bhindi', 1),
            ('Curd', 1),
            ('Apple', 1),
          ]),
        ]),
        TrendRange.week,
        0,
        _now,
      );
      expect(s.topFoods, [
        ('Tea', 2),
        ('Apple', 1),
        ('Bhindi', 1),
        ('Curd', 1),
        ('Dal', 1),
      ]);
    });

    test('nothing logged', () {
      final s = summarizeTrends(_data([]), TrendRange.month, 0, _now);
      expect(s.averagePerLoggedDay, isNull);
      expect(s.topFoods, isEmpty);
    });
  });

  test('niceScale picks clean ticks', () {
    expect(niceScale(0), (1000.0, 500.0));
    expect(niceScale(90), (100.0, 50.0));
    expect(niceScale(1240), (1500.0, 500.0));
    expect(niceScale(3100), (4000.0, 1000.0));
    expect(niceScale(18000), (20000.0, 5000.0));
  });

  testWidgets('tap a bar, then Open day jumps Home to it', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final yesterday = shiftKey(-1);
    await pumpApp(
      tester,
      seed: (r) async {
        await r.saveMeal(_meal('y', yesterday, [('Poha', 250), ('Tea', 90)]));
        await r.saveMeal(_meal('t', todayKey(), [('Dal', null)]));
      },
    );
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    if (DateTime.now().weekday == DateTime.monday) {
      // Yesterday was last week.
      await tester.tap(find.bySemanticsLabel('Previous week'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Most logged'), findsOneWidget);
    expect(find.text('Calories per day'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('bar-$yesterday')));
    await tester.pumpAndSettle();
    expect(find.textContaining('340 kcal · 1 meal'), findsOneWidget);

    await tester.tap(find.text('Open day'));
    await tester.pumpAndSettle();
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(find.textContaining('Poha'), findsOneWidget);
  });

  testWidgets('fits a 320px-wide phone in week and month view', (tester) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(
      tester,
      seed: (r) => r.saveMeal(
        _meal('t', todayKey(), [('Bread Pakora', 12345), ('Sambar', null)]),
      ),
    );
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    // A layout overflow would have thrown during the pumps above.
    expect(find.text('Calories per day'), findsOneWidget);
    expect(find.textContaining('Striped'), findsOneWidget);
  });

  group('Through the day', () {
    Future<void> openTrends(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trends'));
      await tester.pumpAndSettle();
    }

    String pace(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey('day-curve-pace')))
        .textSpan!
        .toPlainText();

    testWidgets('compares today with a saved choice of baseline', (
      tester,
    ) async {
      await pumpApp(
        tester,
        seed: (r) async {
          await r.saveMeal(_meal('t', todayKey(), [('Dal', 400)]));
          await r.saveMeal(_meal('y', shiftKey(-1), [('Rice', 250)]));
          await r.saveMeal(_meal('w', shiftKey(-7), [('Pasta', 900)]));
        },
      );
      await openTrends(tester);
      expect(find.text('Through the day'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      // Meals are at noon, so the numbers depend on the time of the test.
      final noonPassed = DateTime.now().hour >= 12;
      expect(
        pace(tester),
        contains(
          noonPassed ? 'yesterday: 250 kcal · today 400 (+150)' : '(±0)',
        ),
      );

      await tester.tap(
        find.text('Last ${DateFormat('EEE', 'en_US').format(DateTime.now())}'),
      );
      await tester.pumpAndSettle();
      if (noonPassed) {
        expect(pace(tester), contains('900 kcal · today 400 (−500)'));
      }

      // The choice is saved and survives a rebuild of the data.
      final container = ProviderScope.containerOf(
        tester.element(find.text('Through the day')),
      );
      expect(
        container.read(appDataProvider).requireValue.trendBaseline,
        CurveBaseline.lastWeek,
      );
    });

    testWidgets('steps back a day; the baseline is then the day before it', (
      tester,
    ) async {
      await pumpApp(
        tester,
        seed: (r) async {
          await r.saveMeal(_meal('y', shiftKey(-1), [('Rice', 250)]));
          await r.saveMeal(_meal('z', shiftKey(-2), [('Idli', 100)]));
        },
      );
      await openTrends(tester);
      await tester.tap(find.bySemanticsLabel('Previous day'));
      await tester.pumpAndSettle();
      expect(find.text('Day before'), findsOneWidget);
      expect(pace(tester), 'Whole day: 250 kcal · day before 100 (+150)');
      await tester.tap(find.bySemanticsLabel('Next day'));
      await tester.pumpAndSettle();
      expect(find.text('Yesterday'), findsOneWidget);
    });

    testWidgets('tapping a bar shows that day, and tapping the plot reads it', (
      tester,
    ) async {
      final twoAgo = shiftKey(-2);
      await pumpApp(
        tester,
        seed: (r) async {
          await r.saveMeal(
            _meal('z', twoAgo, [('Idli', 100), ('Chutney', null)]),
          );
        },
      );
      await openTrends(tester);
      if (daysAgo(twoAgo) >= DateTime.now().weekday) {
        await tester.tap(find.bySemanticsLabel('Previous week'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(ValueKey('bar-$twoAgo')));
      await tester.pumpAndSettle();
      expect(
        find.text(DateFormat('EEE, MMM d', 'en_US').format(parseKey(twoAgo))),
        findsOneWidget,
      );
      expect(pace(tester), contains('100 kcal · Nothing to compare yet'));
      expect(find.textContaining('Hollow dot'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('day-curve-plot')));
      await tester.pumpAndSettle();
      expect(pace(tester), startsWith('At '));
    });
  });
}
