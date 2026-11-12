import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/data/repository.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

Future<void> _seed(Repository repo) async {
  Meal m(String id, String t, int day, String time, double? cal) => Meal(
    id: id,
    typeId: t,
    date: shiftKey(day),
    time: time,
    entries: [
      MealEntry(id: '$id-1', nameSnapshot: 'Dal', qty: 1, calories: 180),
      MealEntry(id: '$id-2', nameSnapshot: 'Tea', qty: 1, calories: cal),
    ],
  );
  await repo.saveMeal(m('a', 'breakfast', 0, '08:30', 90));
  await repo.saveMeal(m('b', 'dinner', -1, '20:20', null));
  await repo.saveMeal(m('c', 'lunch', -1, '13:00', 90));
}

void main() {
  testWidgets('history groups by day, filters, and swipe-deletes', (
    tester,
  ) async {
    await pumpApp(tester, seed: _seed);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    // Yesterday: 270 complete + 180 incomplete.
    expect(find.text('450+ kcal'), findsOneWidget);
    expect(find.text('270 kcal'), findsNWidgets(3)); // today header + 2 rows

    // Within a day, earliest first.
    final lunchY = tester
        .getTopLeft(find.text('Lunch — 1:00 PM', findRichText: true))
        .dy;
    final dinnerY = tester
        .getTopLeft(find.text('Dinner — 8:20 PM', findRichText: true))
        .dy;
    expect(lunchY, lessThan(dinnerY));

    // Filter.
    await tester.tap(find.text('Dinner'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsNothing);
    expect(find.text('Dinner — 8:20 PM', findRichText: true), findsOneWidget);
    await tester.tap(find.text('Snack'));
    await tester.pumpAndSettle();
    expect(find.text('No meals match this filter.'), findsOneWidget);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    // Swipe to delete asks first; cancelling keeps the meal.
    final row = find.text('Breakfast — 8:30 AM', findRichText: true);
    await tester.drag(row, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete breakfast?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(row, findsOneWidget);

    await tester.drag(row, const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(row, findsNothing);
    expect(find.text('Today'), findsNothing);
  });
}
