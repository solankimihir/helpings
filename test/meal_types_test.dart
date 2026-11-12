import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/database.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/data/repository.dart';
import 'package:helpings/data/seed.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'schema_fixtures.dart';

Meal _meal(String id, String typeId) => Meal(
  id: id,
  typeId: typeId,
  date: todayKey(),
  time: '12:00',
  entries: [MealEntry(id: '$id-e', nameSnapshot: 'Dal')],
);

void main() {
  late Directory dir;
  setUpAll(sqfliteFfiInit);
  setUp(() => dir = Directory.systemTemp.createTempSync('helpings_types'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('guessMealType', () {
    final defaults = [
      for (var i = 0; i < defaultMealTypes.length; i++)
        MealType(
          id: defaultMealTypes[i].$1,
          name: defaultMealTypes[i].$2,
          position: i,
          startMinute: defaultMealTypes[i].$3,
        ),
    ];
    String? at(int h, [int m = 0, List<MealType>? types]) =>
        guessMealType(types ?? defaults, DateTime(2026, 11, 13, h, m))?.id;

    test('follows start times through the day', () {
      expect(at(5), 'breakfast');
      expect(at(10, 59), 'breakfast');
      expect(at(11), 'lunch');
      expect(at(15), 'snack');
      expect(at(18), 'dinner');
      expect(at(23, 59), 'dinner');
    });

    test('before the first start, wraps to last night', () {
      expect(at(2), 'dinner');
    });

    test('skips hidden types', () {
      final noSnack = [
        for (final t in defaults)
          t.id == 'snack' ? t.copyWith(active: false) : t,
      ];
      expect(at(16, 0, noSnack), 'lunch');
    });

    test('with no start times, the first visible type', () {
      final untimed = [
        const MealType(id: 'a', name: 'A', position: 1),
        const MealType(id: 'b', name: 'B', position: 0, active: false),
        const MealType(id: 'c', name: 'C', position: 2),
      ];
      expect(at(9, 0, untimed), 'a');
      expect(guessMealType(const [], DateTime(2026)), isNull);
    });
  });

  test('v1 database migrates: types seeded, meals keep theirs', () async {
    final path = await writeV1('${dir.path}/v1.db');
    final db = await AppDatabase.open(factory: schemaFactory, path: path);
    addTearDown(db.close);
    final r = Repository(db);
    expect((await r.mealTypes()).map((t) => t.name), [
      'Breakfast',
      'Lunch',
      'Dinner',
      'Snack',
      'Other',
    ]);
    final meals = {for (final m in await r.meals()) m.id: m.typeId};
    expect(meals, {'m1': 'snack', 'm2': 'other'});
  });

  test('restoring a v1 backup into the current schema', () async {
    final bytes = File(await writeV1('${dir.path}/v1.db')).readAsBytesSync();
    final db = await AppDatabase.open(
      factory: schemaFactory,
      path: '${dir.path}/live.db',
    );
    addTearDown(db.close);
    final r = Repository(db);
    await r.saveMealType(const MealType(id: 'pre', name: 'Pre-workout'));

    await db.restore(bytes);

    expect((await r.mealTypes()).map((t) => t.id), [
      'breakfast',
      'lunch',
      'dinner',
      'snack',
      'other',
    ]);
    expect((await r.meals()).map((m) => m.typeId), ['snack', 'other']);
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

    test('new types go last; names are unique ignoring case', () async {
      await r.saveMealType(const MealType(id: 'pre', name: 'Pre-workout'));
      expect((await r.mealTypes()).last.id, 'pre');
      expect(
        () => r.saveMealType(const MealType(id: 'x', name: 'lunch')),
        throwsA(isA<DuplicateNameException>()),
      );
    });

    test('reorder rewrites positions', () async {
      await r.reorderMealTypes([
        'other',
        'snack',
        'dinner',
        'lunch',
        'breakfast',
      ]);
      expect((await r.mealTypes()).first.id, 'other');
    });

    test('delete moves meals, or refuses without a target', () async {
      await r.saveMeal(_meal('a', 'snack'));
      expect(() => r.deleteMealType('snack'), throwsA(isA<StateError>()));
      await r.deleteMealType('snack', moveTo: 'other');
      expect((await r.meals()).single.typeId, 'other');
      expect((await r.mealTypes()).map((t) => t.id), isNot(contains('snack')));
    });
  });

  group('settings screen', () {
    Future<void> openTypes(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpApp(tester, seed: (r) => r.saveMeal(_meal('m', 'snack')));
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Meal types'));
      await tester.pumpAndSettle();
    }

    Future<void> back(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
    }

    Finder chip(String label) =>
        find.descendant(of: find.byType(Wrap), matching: find.text(label));

    testWidgets('add a type; it is offered when adding a meal', (tester) async {
      await openTypes(tester);
      await tester.tap(find.text('+ Add'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Pre-workout');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Pre-workout'), findsOneWidget);

      await back(tester);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ Add Meal'));
      await tester.pumpAndSettle();
      expect(chip('Pre-workout'), findsOneWidget);
    });

    testWidgets('rename shows on existing meals', (tester) async {
      await openTypes(tester);
      await tester.tap(find.text('Snack'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Tea time');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await back(tester);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Tea time'), findsOneWidget);
    });

    testWidgets('hiding removes the chip but keeps it on the meal', (
      tester,
    ) async {
      await openTypes(tester);
      await tester.tap(find.text('Snack'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('from 3:00 PM · hidden'), findsOneWidget);

      await back(tester);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Snack'), findsOneWidget); // the existing meal card
      await tester.tap(find.text('+ Add Meal'));
      await tester.pumpAndSettle();
      expect(chip('Snack'), findsNothing);
      expect(chip('Lunch'), findsOneWidget);
    });

    testWidgets('deleting a used type moves its meals', (tester) async {
      await openTypes(tester);
      await tester.tap(find.text('Snack'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete meal type'));
      await tester.pumpAndSettle();
      expect(find.text('Move its 1 meal to:'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Dinner'),
        ),
      );
      await tester.tap(find.text('Move & delete'));
      await tester.pumpAndSettle();
      expect(find.text('Snack'), findsNothing);

      await back(tester);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Dinner'), findsOneWidget);
    });
  });
}
