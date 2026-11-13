import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/data/trends.dart';
import 'package:helpings/state/app_state.dart';
import 'package:helpings/ui/trends_view.dart';
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
}
