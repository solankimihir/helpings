import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/database.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/data/repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'schema_fixtures.dart';

const _scoop = FoodUnit(id: 'scoop', name: 'Scoop');
const _whey = FoodItem(
  id: 'whey',
  name: 'Whey',
  defaultCalories: 120,
  defaultUnit: _scoop,
);

Meal _meal(FoodUnit unit) => Meal(
  id: 'm',
  typeId: 'snack',
  date: todayKey(),
  time: '16:00',
  entries: [
    MealEntry(
      id: 'e',
      itemId: 'whey',
      nameSnapshot: 'Whey',
      qty: 2,
      unit: unit,
      calories: 240,
    ),
  ],
);

void main() {
  late Directory dir;
  setUpAll(sqfliteFfiInit);
  setUp(() => dir = Directory.systemTemp.createTempSync('helpings_units'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('formats any unit, pluralised', () {
    expect(lineText('Whey', 2, _scoop), '2 scoops Whey');
    expect(lineText('Whey', 1, _scoop), '1 scoop Whey');
    const glass = FoodUnit(id: 'g2', name: 'Glass');
    expect(lineText('Milk', 2, glass), '2 glasses Milk');
    expect(qtyLabel(2, glass), '2 Glasses');
    expect(qtyLabel(3, const FoodUnit(id: 'p', name: 'Pieces')), '3 Pieces');
  });

  test('a v1 database gains the built-in units', () async {
    final path = await writeV1('${dir.path}/v1.db');
    final db = await AppDatabase.open(factory: schemaFactory, path: path);
    addTearDown(db.close);
    final units = await Repository(db).units();
    expect(units.map((u) => u.id), ['piece', 'gram', 'spoon', 'cup']);
    expect(units.map((u) => u.name), ['Piece', 'Gram', 'Spoon', 'Cup']);
  });

  test('upgrading to v6 keeps the units foods and meals use', () async {
    final path = '${dir.path}/v5.db';
    var db = await AppDatabase.open(factory: schemaFactory, path: path);
    var r = Repository(db);
    await r.saveItem(_whey.copyWith(defaultUnit: () => FoodUnit.cup));
    await r.saveMeal(_meal(FoodUnit.spoon));
    await db.db.execute('DROP TABLE units');
    await db.db.setVersion(5);
    await db.close();

    db = await AppDatabase.open(factory: schemaFactory, path: path);
    addTearDown(db.close);
    r = Repository(db);
    expect((await r.units()), hasLength(4));
    expect(
      (await r.items()).firstWhere((i) => i.id == 'whey').defaultUnit,
      (FoodUnit.cup),
    );
    expect((await r.meals()).single.entries.single.unit?.name, 'Spoon');
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

    test('add, rename and reorder; names show on foods and meals', () async {
      await r.saveUnit(_scoop);
      expect((await r.units()).last.name, 'Scoop');
      await r.saveItem(_whey);
      await r.saveMeal(_meal(_scoop));

      await r.saveUnit(_scoop.copyWith(name: 'Big scoop'));
      final item = (await r.items()).firstWhere((i) => i.id == 'whey');
      expect(item.defaultUnit?.name, 'Big scoop');
      expect((await r.meals()).single.entries.single.unit?.name, 'Big scoop');

      await r.reorderUnits(['scoop', 'piece', 'gram', 'spoon', 'cup']);
      expect((await r.units()).first.id, 'scoop');
    });

    test('names are unique, built-ins keep theirs', () async {
      expect(
        () => r.saveUnit(const FoodUnit(id: 'x', name: 'CUP')),
        throwsA(isA<DuplicateNameException>()),
      );
      await r.saveUnit(FoodUnit.cup.copyWith(name: 'Mug', active: false));
      final cup = (await r.units()).firstWhere((u) => u.id == 'cup');
      expect((cup.name, cup.active), ('Cup', false));
    });

    test('only unused custom units can be deleted', () async {
      await r.saveUnit(_scoop);
      await r.saveItem(_whey);
      expect(await r.unitUsageCount('scoop'), 1);
      expect(() => r.deleteUnit('scoop'), throwsStateError);
      expect(() => r.deleteUnit('cup'), throwsStateError);

      await r.saveItem(_whey.copyWith(defaultUnit: () => null));
      expect(await r.unitUsageCount('scoop'), 0);
      await r.deleteUnit('scoop');
      expect((await r.units()).map((u) => u.id), isNot(contains('scoop')));
    });

    test('pastLines treats a custom unit like any other', () async {
      await r.saveUnit(_scoop);
      await r.saveItem(_whey.copyWith(defaultCalories: () => null));
      await r.saveMeal(
        Meal(
          id: 'm',
          typeId: 'snack',
          date: todayKey(),
          time: '16:00',
          entries: const [
            MealEntry(
              id: 'e',
              itemId: 'whey',
              nameSnapshot: 'Whey',
              qty: 2,
              unit: _scoop,
            ),
          ],
        ),
      );
      final before = (await r.items()).firstWhere((i) => i.id == 'whey');
      final lines = await r.pastLines(before, _whey);
      expect(lines.fillable, ['e']);
      await r.applyPastLines(_whey, lines.fillable);
      expect((await r.meals()).single.entries.single.calories, 240);
    });
  });

  group('settings screen', () {
    Future<void> openUnits(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpApp(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Units'));
      await tester.pumpAndSettle();
    }

    testWidgets('add a unit; it is offered for new foods', (tester) async {
      await openUnits(tester);
      await tester.tap(find.text('+ Add'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Scoop');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Scoop'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Piece · Gram · Spoon · Cup · Scoop'), findsOneWidget);
      // The default-unit picker offers it.
      await tester.tap(find.text('Piece'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scoop').last);
      await tester.pumpAndSettle();
      expect(find.text('Scoop'), findsOneWidget);
      expect(find.text('Piece'), findsNothing);
    });

    testWidgets('a hidden unit leaves the pickers', (tester) async {
      await openUnits(tester);
      await tester.tap(find.text('Spoon'));
      await tester.pumpAndSettle();
      expect(find.text('Delete unit'), findsNothing); // built in
      await tester.tap(find.byType(Switch));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('built in · hidden'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Piece · Gram · Cup'), findsOneWidget);
    });
  });
}
