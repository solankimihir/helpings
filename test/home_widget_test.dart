import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/home_widget_data.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/state/app_state.dart';
import 'package:helpings/ui/meal_sheet.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

Meal _meal(String id, String date, List<double?> cals) => Meal(
  id: id,
  typeId: 'lunch',
  date: date,
  time: '12:00',
  entries: [
    for (final (i, c) in cals.indexed)
      MealEntry(id: '$id-$i', nameSnapshot: 'Item $i', calories: c),
  ],
);

void main() {
  test('payload counts only today, rounds, and flags missing calories', () {
    final now = DateTime(2026, 11, 13, 9);
    final data = AppData(
      items: const [],
      meals: [
        _meal('y', '2026-11-12', [500]),
        _meal('a', '2026-11-13', [200.4, 90]),
        _meal('b', '2026-11-13', [null]),
      ],
      defaultUnit: FoodUnit.piece,
    );
    final p = WidgetPayload.of(data, now);
    expect(p.date, '2026-11-13');
    expect(p.calories, 290);
    expect(p.meals, 2);
    expect(p.items, 3);
    expect(p.incomplete, isTrue);
  });

  test('payload lists today’s meals in time order with their foods', () {
    final now = DateTime(2026, 11, 13, 21);
    final data = AppData(
      items: const [],
      mealTypes: const [
        MealType(id: 'breakfast', name: 'Breakfast'),
        MealType(id: 'dinner', name: 'Dinner'),
      ],
      meals: [
        _meal('y', '2026-11-12', [500]),
        // Saved out of order: dinner first.
        Meal(
          id: 'd',
          typeId: 'dinner',
          date: '2026-11-13',
          time: '20:15',
          entries: const [
            MealEntry(
              id: 'd1',
              nameSnapshot: 'Rice',
              qty: 150,
              unit: FoodUnit.gram,
              calories: 195,
            ),
            MealEntry(id: 'd2', nameSnapshot: 'Pickle'),
          ],
        ),
        Meal(
          id: 'b',
          typeId: 'breakfast',
          date: '2026-11-13',
          time: '08:30',
          entries: const [
            MealEntry(
              id: 'b1',
              nameSnapshot: 'Idli',
              qty: 2,
              unit: FoodUnit.piece,
              calories: 116.4,
            ),
          ],
        ),
      ],
      defaultUnit: FoodUnit.piece,
    );
    expect(WidgetPayload.of(data, now).lines, const [
      WidgetLine.meal('Breakfast · 8:30 AM', '116 kcal'),
      WidgetLine.item('2 Idli', '116'),
      WidgetLine.meal('Dinner · 8:15 PM', '195+ kcal'),
      WidgetLine.item('150 g Rice', '195'),
      WidgetLine.item('Pickle', ''),
    ]);
  });

  test('renaming a food today changes the payload', () {
    final now = DateTime(2026, 11, 13, 9);
    WidgetPayload of(String name) => WidgetPayload.of(
      AppData(
        items: const [],
        meals: [
          Meal(
            id: 'a',
            typeId: 'lunch',
            date: '2026-11-13',
            time: '12:00',
            entries: [MealEntry(id: 'a1', nameSnapshot: name, calories: 100)],
          ),
        ],
        defaultUnit: FoodUnit.piece,
      ),
      now,
    );
    expect(of('Dal'), of('Dal'));
    expect(of('Dal'), isNot(of('Dal fry')));
  });

  testWidgets('publishes on start and after each change', (tester) async {
    final widget = FakeHomeWidgetBridge();
    await pumpApp(
      tester,
      homeWidget: widget,
      seed: (r) => r.saveMeal(_meal('a', todayKey(), [300])),
    );
    expect(widget.published.single.calories, 300);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    await tester.runAsync(
      () => container
          .read(appDataProvider.notifier)
          .saveMeal(_meal('b', todayKey(), [150])),
    );
    await tester.pumpAndSettle();
    expect(widget.published.last.calories, 450);
    expect(widget.published.last.meals, 2);
    expect(widget.published.last.items, 2);

    // A change that doesn't affect today (yesterday's meal) isn't re-sent.
    final sent = widget.published.length;
    await tester.runAsync(
      () => container
          .read(appDataProvider.notifier)
          .saveMeal(_meal('c', shiftKey(-1), [999])),
    );
    await tester.pumpAndSettle();
    expect(widget.published, hasLength(sent));
  });

  testWidgets('the widget’s Add meal button opens Add Meal', (tester) async {
    final widget = FakeHomeWidgetBridge();
    await pumpApp(tester, homeWidget: widget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    widget.click(widgetAddMealUri);
    await tester.pumpAndSettle();
    expect(find.byType(MealSheet), findsOneWidget);
  });

  testWidgets('a tap on the widget body just opens Home', (tester) async {
    final widget = FakeHomeWidgetBridge();
    await pumpApp(tester, homeWidget: widget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    widget.click(Uri.parse('helpings://today'));
    await tester.pumpAndSettle();
    expect(find.byType(MealSheet), findsNothing);
    expect(find.text('TODAY'), findsOneWidget);
  });

  testWidgets('launching from the Add meal button opens Add Meal', (
    tester,
  ) async {
    await pumpApp(
      tester,
      homeWidget: FakeHomeWidgetBridge(launchedWith: widgetAddMealUri),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MealSheet), findsOneWidget);
  });
}
