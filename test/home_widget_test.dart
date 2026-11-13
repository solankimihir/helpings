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
    expect(
      WidgetPayload.of(data, now),
      const WidgetPayload(
        date: '2026-11-13',
        calories: 290,
        meals: 2,
        incomplete: true,
      ),
    );
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
