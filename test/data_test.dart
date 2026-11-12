import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/database.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/data/repository.dart';
import 'package:helpings/data/seed.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late Repository repo;

  setUp(() async {
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = Repository(db);
  });
  tearDown(() => db.close());

  Meal sampleMeal(String id, {String date = '2026-11-12'}) => Meal(
    id: id,
    type: MealType.lunch,
    date: date,
    time: '13:15',
    notes: 'Office canteen',
    entries: [
      MealEntry(
        id: '$id-e1',
        nameSnapshot: 'Roti',
        qty: 2,
        unit: FoodUnit.piece,
        calories: 200,
      ),
      MealEntry(
        id: '$id-e2',
        nameSnapshot: 'Sambar',
        qty: 1,
        unit: FoodUnit.cup,
      ),
    ],
  );

  test('first launch seeds default food items only', () async {
    final items = await repo.items();
    expect(items.length, defaultItems.length);
    expect(items.every((i) => i.active), isTrue);
    expect(await repo.meals(), isEmpty);
    final sambar = items.firstWhere((i) => i.name == 'Sambar');
    expect(sambar.defaultCalories, isNull);
    expect(sambar.defaultUnit, FoodUnit.cup);
  });

  test('restoreDefaultItems only adds missing names', () async {
    final roti = (await repo.items()).firstWhere((i) => i.name == 'Roti');
    await repo.deleteItem(roti.id);
    await repo.saveItem(
      (await repo.items())
          .firstWhere((i) => i.name == 'Dal')
          .copyWith(defaultCalories: () => 999),
    );
    expect(await repo.restoreDefaultItems(), 1);
    final items = await repo.items();
    expect(items.length, defaultItems.length);
    expect(items.firstWhere((i) => i.name == 'Dal').defaultCalories, 999);
  });

  test('item names are unique case-insensitively', () async {
    await expectLater(
      repo.saveItem(const FoodItem(id: 'x', name: 'roti')),
      throwsA(isA<DuplicateNameException>()),
    );
    // Renaming an item to its own name in a different case is allowed.
    final roti = (await repo.items()).firstWhere((i) => i.name == 'Roti');
    await repo.saveItem(roti.copyWith(name: 'ROTI'));
    expect((await repo.items()).any((i) => i.name == 'ROTI'), isTrue);
  });

  test('meal round-trip keeps entry order and null calories', () async {
    await repo.saveMeal(sampleMeal('m1'));
    final meals = await repo.meals();
    expect(meals, hasLength(1));
    final m = meals.single;
    expect(m.type, MealType.lunch);
    expect(m.notes, 'Office canteen');
    expect(m.entries.map((e) => e.nameSnapshot), ['Roti', 'Sambar']);
    expect(m.entries[1].calories, isNull);
    expect(m.totals.sum, 200);
    expect(m.totals.missing, 1);
    expect(m.totals.complete, isFalse);
  });

  test('editing a meal replaces its entries', () async {
    await repo.saveMeal(sampleMeal('m1'));
    await repo.saveMeal(
      Meal(
        id: 'm1',
        type: MealType.dinner,
        date: '2026-11-12',
        time: '20:00',
        entries: const [
          MealEntry(id: 'e9', nameSnapshot: 'Dal', qty: 1, calories: 180),
        ],
      ),
    );
    final m = (await repo.meals()).single;
    expect(m.type, MealType.dinner);
    expect(m.entries.single.nameSnapshot, 'Dal');
    expect(m.totals.complete, isTrue);
  });

  test('deleting a meal cascades to its entries', () async {
    await repo.saveMeal(sampleMeal('m1'));
    await repo.deleteMeal('m1');
    final n = await db.db.rawQuery('SELECT COUNT(*) AS n FROM meal_entries');
    expect(n.first['n'], 0);
  });

  test('deleting a food item keeps the logged name', () async {
    final roti = (await repo.items()).firstWhere((i) => i.name == 'Roti');
    await repo.saveMeal(
      Meal(
        id: 'm1',
        type: MealType.lunch,
        date: '2026-11-12',
        time: '12:00',
        entries: [
          MealEntry(
            id: 'e1',
            itemId: roti.id,
            nameSnapshot: 'Roti',
            qty: 2,
            calories: 200,
          ),
        ],
      ),
    );
    expect(await repo.itemUsageCount(roti.id), 1);
    await repo.deleteItem(roti.id);
    final e = (await repo.meals()).single.entries.single;
    expect(e.itemId, isNull);
    expect(e.nameSnapshot, 'Roti');
  });

  test('meals are ordered by date then time', () async {
    await repo.saveMeal(sampleMeal('b', date: '2026-11-12'));
    await repo.saveMeal(sampleMeal('a', date: '2026-11-10'));
    expect((await repo.meals()).map((m) => m.id), ['a', 'b']);
  });

  test('settings persist', () async {
    expect(await repo.setting('default_unit'), isNull);
    await repo.setSetting('default_unit', 'gram');
    expect(await repo.setting('default_unit'), 'gram');
  });
}
