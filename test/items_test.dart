import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/data/repository.dart';
import 'package:helpings/data/seed.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

Finder _search() => find.widgetWithText(TextField, 'Search food items');

void main() {
  testWidgets('meal items: search, create, edit, deactivate, delete', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Meal Items').last);
    await tester.pumpAndSettle();
    expect(find.text('${defaultItems.length} ITEMS'), findsOneWidget);

    // Search narrows the list and offers to create a missing name.
    await tester.enterText(_search(), 'Paneer');
    await tester.pumpAndSettle();
    expect(find.text('0 ITEMS'), findsOneWidget);
    await tester.tap(find.text('+ Create “Paneer”'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('${defaultItems.length + 1} ITEMS'), findsOneWidget);

    // Duplicate names are rejected.
    await tester.tap(find.text('+ New'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'e.g. Roti'), 'roti');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('“Roti” already exists.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Deactivate sinks the item to the bottom and tags it.
    await tester.enterText(_search(), 'Tea');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();
    expect(find.text('Tea  Inactive', findRichText: true), findsOneWidget);
    expect(find.text('Activate'), findsOneWidget);

    // Edit defaults.
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Meal Item'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '90'), '45');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('45 kcal · Cup'), findsOneWidget);

    // Delete.
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete food item'));
    await tester.pumpAndSettle();
    expect(find.text('It isn’t used in any logged meal.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('0 ITEMS'), findsOneWidget);
  });

  group('giving a food calories later', () {
    const toast = FoodItem(
      id: 'toast',
      name: 'Toast Sandwich',
      defaultUnit: FoodUnit.piece,
    );
    Future<void> seed(Repository r, {double? typed}) async {
      await r.saveItem(toast);
      await r.saveMeal(
        Meal(
          id: 'm',
          typeId: 'lunch',
          date: todayKey(),
          time: '13:00',
          entries: [
            const MealEntry(
              id: 'e',
              itemId: 'toast',
              nameSnapshot: 'Toast Sandwich',
              qty: 2,
              unit: FoodUnit.piece,
            ),
            if (typed != null)
              MealEntry(
                id: 'f',
                itemId: 'toast',
                nameSnapshot: 'Toast Sandwich',
                qty: 1,
                unit: FoodUnit.piece,
                calories: typed,
              ),
          ],
        ),
      );
    }

    Future<List<double?>> loggedAll(WidgetTester tester, db) async =>
        (await tester.runAsync(() => Repository(db).meals()))!.single.entries
            .map((e) => e.calories)
            .toList();

    Future<double?> logged(WidgetTester tester, db) async =>
        (await loggedAll(tester, db)).first;

    Future<void> setCalories(WidgetTester tester) async {
      await tester.tap(find.text('Meal Items').last);
      await tester.pumpAndSettle();
      await tester.enterText(_search(), 'Toast');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'optional'), '150');
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(find.text('Update past meals?'), findsOneWidget);
      expect(
        find.text('Fill in 1 logged line that has no calories'),
        findsOneWidget,
      );
    }

    testWidgets('offers to fill in past meals', (tester) async {
      final db = await pumpApp(tester, seed: seed);
      await setCalories(tester);
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(find.text('Update past meals?'), findsNothing);
      expect(await logged(tester, db), 300); // 2 pieces × 150
    });

    testWidgets('lines with other calories are offered, unticked', (
      tester,
    ) async {
      final db = await pumpApp(tester, seed: (r) => seed(r, typed: 10));
      await setCalories(tester);
      expect(
        find.text('Replace 1 logged line that has different calories'),
        findsOneWidget,
      );
      expect(find.text('Currently 10 kcal'), findsOneWidget);

      // By default only the blank line is filled.
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(await loggedAll(tester, db), [300, 10]);
    });

    testWidgets('ticking it replaces the typed value too', (tester) async {
      final db = await pumpApp(tester, seed: (r) => seed(r, typed: 10));
      await setCalories(tester);
      await tester.tap(
        find.text('Replace 1 logged line that has different calories'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(await loggedAll(tester, db), [300, 150]);
    });

    testWidgets('leave as is keeps them blank', (tester) async {
      final db = await pumpApp(tester, seed: seed);
      await setCalories(tester);
      await tester.tap(find.text('Leave as is'));
      await tester.pumpAndSettle();
      expect(await logged(tester, db), isNull);
    });
  });
}
