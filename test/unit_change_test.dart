import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/database.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/data/repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'schema_fixtures.dart';

const _toast = FoodItem(
  id: 'toast',
  name: 'Toast Sandwich',
  defaultCalories: 150,
  defaultUnit: FoodUnit.piece,
);

MealEntry _line(String id, FoodUnit? unit, {double? cal}) => MealEntry(
  id: id,
  itemId: 'toast',
  nameSnapshot: 'Toast Sandwich',
  qty: 2,
  unit: unit,
  calories: cal,
);

Future<void> _seed(Repository r) async {
  await r.saveItem(_toast);
  await r.saveMeal(
    Meal(
      id: 'm',
      typeId: 'lunch',
      date: todayKey(),
      time: '13:00',
      entries: [
        _line('a', FoodUnit.piece, cal: 300),
        _line('b', FoodUnit.gram, cal: 50),
      ],
    ),
  );
  await r.saveCombo(
    Combo(id: 'c', name: 'Lunch', items: [_line('ci', FoodUnit.piece)]),
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('repository', () {
    late Repository r;
    setUp(() async {
      final db = await AppDatabase.open(
        factory: schemaFactory,
        path: inMemoryDatabasePath,
      );
      addTearDown(db.close);
      r = Repository(db);
      await _seed(r);
    });

    test('finds and moves lines in the old unit, then undoes', () async {
      final lines = await r.unitLines('toast', FoodUnit.piece);
      expect(lines.logged, ['a']);
      expect(lines.combo, ['ci']);

      final snap = await r.snapshotLines('toast');
      expect(await r.setLineUnits('toast', lines, FoodUnit.cup), 2);
      var entries = (await r.meals()).single.entries;
      expect(entries.map((e) => e.unit), [FoodUnit.cup, FoodUnit.gram]);
      expect(entries.map((e) => e.calories), [300, 50]); // calories stay
      expect((await r.combos()).single.items.single.unit, FoodUnit.cup);

      await r.applyPastLines(_toast.copyWith(defaultUnit: () => FoodUnit.cup), [
        'a',
      ]);
      await r.restoreLines(snap);
      entries = (await r.meals()).single.entries;
      expect(entries.map((e) => e.unit), [FoodUnit.piece, FoodUnit.gram]);
      expect(entries.map((e) => e.calories), [300, 50]);
      expect((await r.combos()).single.items.single.unit, FoodUnit.piece);
    });
  });

  group('editing the food', () {
    Future<AppDatabase> changeUnitToCup(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = await pumpApp(tester, seed: _seed);
      await tester.tap(find.text('Meal Items').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search food items'),
        'Toast',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Piece').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cup').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(find.text('Change unit on past meals?'), findsOneWidget);
      expect(
        find.textContaining(
          '1 logged line and 1 combo line of “Toast Sandwich” use “Piece”',
        ),
        findsOneWidget,
      );
      return db;
    }

    Future<List<FoodUnit?>> units(WidgetTester tester, AppDatabase db) async =>
        (await tester.runAsync(() => Repository(db).meals()))!.single.entries
            .map((e) => e.unit)
            .toList();

    testWidgets('changes the unit, and Undo puts it back', (tester) async {
      final db = await changeUnitToCup(tester);
      await tester.tap(find.text('Change to Cup'));
      await tester.pumpAndSettle();
      // 2 cups at 150 is already the logged 300, so no calorie prompt.
      expect(find.text('Update past meals?'), findsNothing);
      expect(await units(tester, db), [FoodUnit.cup, FoodUnit.gram]);
      expect(find.text('Changed the unit on 2 lines'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(await units(tester, db), [FoodUnit.piece, FoodUnit.gram]);
      expect(find.text('Past meals put back'), findsOneWidget);
    });

    testWidgets('Undo goes away after 30 seconds', (tester) async {
      await changeUnitToCup(tester);
      await tester.tap(find.text('Change to Cup'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 29));
      expect(find.text('Undo'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('Keep leaves past meals alone', (tester) async {
      final db = await changeUnitToCup(tester);
      await tester.tap(find.text('Keep Piece'));
      await tester.pumpAndSettle();
      if (find.text('Leave as is').evaluate().isNotEmpty) {
        await tester.tap(find.text('Leave as is'));
        await tester.pumpAndSettle();
      }
      expect(await units(tester, db), [FoodUnit.piece, FoodUnit.gram]);
      expect(find.text('Undo'), findsNothing);
    });
  });

  testWidgets('a new meal line takes the food’s current unit', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(
      tester,
      seed: (r) async {
        await r.saveItem(_toast.copyWith(defaultUnit: () => FoodUnit.spoon));
        await r.setSetting('default_unit', 'gram');
      },
    );
    await tester.tap(find.text('+ Add Meal'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search food — e.g. Roti'),
      'Toast',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toast Sandwich  150', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('Spoon'), findsOneWidget);
    expect(find.text('Gram'), findsNothing);
  });
}
