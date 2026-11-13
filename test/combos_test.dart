import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/database.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/data/repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'schema_fixtures.dart';

const _usual = Combo(
  id: 'c1',
  name: 'Usual breakfast',
  items: [
    MealEntry(id: 'l1', nameSnapshot: 'Roti', qty: 2, calories: 200),
    MealEntry(id: 'l2', nameSnapshot: 'Tea', qty: 1, calories: 90),
  ],
);

void main() {
  late Directory dir;
  setUpAll(sqfliteFfiInit);
  setUp(() => dir = Directory.systemTemp.createTempSync('helpings_combos'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('v2 database migrates and gains combos', () async {
    final path = await writeV2('${dir.path}/v2.db');
    final db = await AppDatabase.open(factory: schemaFactory, path: path);
    addTearDown(db.close);
    final r = Repository(db);
    expect(await r.combos(), isEmpty);
    await r.saveCombo(_usual);
    expect((await r.combos()).single.items, hasLength(2));
    expect((await r.meals()).map((m) => m.typeId), ['snack', 'other']);
  });

  test('a v2 backup restores into the current schema', () async {
    final bytes = File(await writeV2('${dir.path}/v2.db')).readAsBytesSync();
    final db = await AppDatabase.open(
      factory: schemaFactory,
      path: '${dir.path}/live.db',
    );
    addTearDown(db.close);
    final r = Repository(db);
    await r.saveCombo(_usual);
    await db.restore(bytes);
    expect(await r.combos(), isEmpty); // the backup had none
    expect(await r.meals(), hasLength(2));
  });

  group('repository', () {
    late Repository r;
    setUp(() async {
      final db = await AppDatabase.open(
        factory: schemaFactory,
        path: inMemoryDatabasePath,
      );
      addTearDown(db.close);
      r = Repository(db);
    });

    test('save, rename, unique names, delete', () async {
      await r.saveCombo(_usual);
      final saved = (await r.combos()).single;
      expect(saved.items.map((e) => e.nameSnapshot), ['Roti', 'Tea']);
      expect(saved.items.first.qty, 2);

      await r.saveCombo(saved.copyWith(name: 'Weekday breakfast'));
      expect((await r.combos()).single.name, 'Weekday breakfast');

      expect(
        () => r.saveCombo(const Combo(id: 'c2', name: 'weekday BREAKFAST')),
        throwsA(isA<DuplicateNameException>()),
      );

      await r.deleteCombo('c1');
      expect(await r.combos(), isEmpty);
    });

    test('deleting a food item keeps its name in the combo', () async {
      final roti = (await r.items()).firstWhere((i) => i.name == 'Roti');
      await r.saveCombo(
        Combo(
          id: 'c',
          name: 'Just roti',
          items: [MealEntry(id: 'l', itemId: roti.id, nameSnapshot: 'Roti')],
        ),
      );
      await r.deleteItem(roti.id);
      final line = (await r.combos()).single.items.single;
      expect(line.itemId, isNull);
      expect(line.nameSnapshot, 'Roti');
    });
  });

  testWidgets('save a combo from Add Meal, then add it in one tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = await pumpApp(tester);
    final search = find.widgetWithText(TextField, 'Search food — e.g. Roti');

    await tester.tap(find.text('+ Add Meal'));
    await tester.pumpAndSettle();
    // Always visible; with nothing added yet it explains what to do.
    await tester.tap(find.text('Save as combo'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Add the items you eat together first'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);

    await tester.enterText(search, 'rot');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roti  100', findRichText: true));
    await tester.pumpAndSettle();
    await tester.enterText(search, 'tea');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tea  90', findRichText: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save as combo'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Usual breakfast',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Save'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Usual breakfast'), findsOneWidget);

    // A new meal: one tap adds both lines.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ Add Meal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usual breakfast'));
    await tester.pumpAndSettle();
    // Adding scrolls the sheet down to the search box, so check the saved
    // meal rather than rows that may be offscreen.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final meal = (await tester.runAsync(() => Repository(db).meals()))!.single;
    expect(meal.entries.map((e) => (e.nameSnapshot, e.calories)), [
      ('Roti', 100.0),
      ('Tea', 90.0),
    ]);
  });

  group('Settings > Combos', () {
    Future<void> openCombos(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpApp(tester, seed: (r) => r.saveCombo(_usual));
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Combos'));
      await tester.pumpAndSettle();
      expect(find.text('2 Roti · 1 Tea · 290 kcal'), findsOneWidget);
    }

    Finder field(String hint) => find.widgetWithText(TextField, hint);

    testWidgets('+ New builds a combo without logging a meal', (tester) async {
      await openCombos(tester);
      await tester.tap(find.text('+ New'));
      await tester.pumpAndSettle();
      expect(find.text('New Combo'), findsOneWidget);

      await tester.enterText(field('e.g. Usual breakfast'), 'Light dinner');
      await tester.enterText(field('Search food — e.g. Roti'), 'dal');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dal  180', findRichText: true));
      await tester.pumpAndSettle();
      await tester.enterText(field('Search food — e.g. Roti'), 'rot');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roti  100', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.text('280 kcal'), findsOneWidget); // live total

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Light dinner'), findsOneWidget);
      expect(find.text('1 cup Dal · 1 Roti · 280 kcal'), findsOneWidget);
    });

    testWidgets('tapping a combo edits its name and items', (tester) async {
      await openCombos(tester);
      await tester.tap(find.text('Usual breakfast'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Combo'), findsOneWidget);

      await tester.enterText(
        field('e.g. Usual breakfast'),
        'Weekday breakfast',
      );
      await tester.tap(find.byIcon(Icons.close_rounded).last); // drop Tea
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Weekday breakfast'), findsOneWidget);
      expect(find.text('2 Roti · 200 kcal'), findsOneWidget);
    });

    testWidgets('a combo can be deleted from its row', (tester) async {
      await openCombos(tester);
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No combos yet'), findsOneWidget);
    });

    testWidgets('a combo can be deleted from its editor', (tester) async {
      await openCombos(tester);
      await tester.tap(find.text('Usual breakfast'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete combo'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No combos yet'), findsOneWidget);
    });

    testWidgets('a combo name must be unique', (tester) async {
      await openCombos(tester);
      await tester.tap(find.text('+ New'));
      await tester.pumpAndSettle();
      await tester.enterText(field('e.g. Usual breakfast'), 'usual BREAKFAST');
      await tester.enterText(field('Search food — e.g. Roti'), 'tea');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tea  90', findRichText: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('already exists'), findsOneWidget);
      expect(find.text('New Combo'), findsOneWidget); // still open
    });
  });
}
