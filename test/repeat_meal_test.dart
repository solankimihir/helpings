import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/data/repository.dart';
import 'package:helpings/ui/meal_sheet.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

final _yesterdayLunch = Meal(
  id: 'y',
  typeId: 'lunch',
  date: shiftKey(-1),
  time: '13:00',
  notes: 'spicy',
  entries: const [
    MealEntry(id: 'y-e', nameSnapshot: 'Dal', qty: 2, calories: 180),
  ],
);

Finder _inSheet(String text) => find.descendant(
  of: find.byType(MealSheet),
  matching: find.text(text, findRichText: true),
);

void main() {
  testWidgets('Log again copies a past meal into a new one for today', (
    tester,
  ) async {
    late Repository repo;
    await pumpApp(
      tester,
      seed: (r) async {
        repo = r;
        await r.saveMeal(_yesterdayLunch);
      },
    );
    // Yesterday on Home, then its meal.
    await tester.fling(find.byType(PageView), const Offset(400, 0), 1500);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lunch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log again'));
    await tester.pumpAndSettle();

    expect(_inSheet('Add Meal'), findsOneWidget);
    expect(_inSheet('Today'), findsOneWidget);
    expect(find.widgetWithText(TextField, '180'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final meals = await tester.runAsync(repo.meals);
    expect(meals, hasLength(2));
    final copy = meals!.firstWhere((m) => m.id != 'y');
    expect(copy.date, todayKey());
    expect(copy.typeId, 'lunch');
    expect(copy.notes, 'spicy');
    expect(copy.entries.single.nameSnapshot, 'Dal');
    expect(copy.entries.single.qty, 2);
    expect(copy.entries.single.id, isNot('y-e'));
  });

  testWidgets('suggests the same meal as yesterday for the chosen type', (
    tester,
  ) async {
    await pumpApp(tester, seed: (r) => r.saveMeal(_yesterdayLunch));
    await tester.tap(find.text('+ Add Meal'));
    await tester.pumpAndSettle();
    const suggestion = '↻ Same as yesterday’s Lunch';

    await tester.tap(_inSheet('Dinner'));
    await tester.pumpAndSettle();
    expect(find.textContaining('↻ Same as'), findsNothing);

    await tester.tap(_inSheet('Lunch'));
    await tester.pumpAndSettle();
    expect(find.text(suggestion), findsOneWidget);
    await tester.tap(find.text(suggestion));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '180'), findsOneWidget);
    // Once items are added the suggestion goes away.
    expect(find.text(suggestion), findsNothing);
  });
}
