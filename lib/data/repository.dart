import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'models.dart';
import 'seed.dart';

class DuplicateNameException implements Exception {
  DuplicateNameException(this.existingName);
  final String existingName;

  @override
  String toString() => '“$existingName” already exists.';
}

/// All reads and writes go through here.
class Repository {
  Repository(this._appDb);

  final AppDatabase _appDb;
  Database get _db => _appDb.db;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  // ---- Food items ---------------------------------------------------------

  Future<List<FoodItem>> items() async {
    final rows = await _db.query('food_items', orderBy: 'name COLLATE NOCASE');
    return rows.map(FoodItem.fromRow).toList();
  }

  /// Inserts or updates. Throws [DuplicateNameException] if another item
  /// already uses the name (case-insensitive).
  Future<void> saveItem(FoodItem item) async {
    final clash = await _db.query(
      'food_items',
      columns: ['name'],
      where: 'name = ? COLLATE NOCASE AND id != ?',
      whereArgs: [item.name, item.id],
      limit: 1,
    );
    if (clash.isNotEmpty) {
      throw DuplicateNameException(clash.first['name'] as String);
    }
    final updated = await _db.update(
      'food_items',
      item.toRow(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
    if (updated == 0) {
      await _db.insert('food_items', {...item.toRow(), 'created_at': _now});
    }
  }

  Future<void> setItemActive(String id, bool active) => _db.update(
    'food_items',
    {'active': active ? 1 : 0},
    where: 'id = ?',
    whereArgs: [id],
  );

  /// Meals that used the item keep its name via `name_snapshot`.
  Future<void> deleteItem(String id) =>
      _db.delete('food_items', where: 'id = ?', whereArgs: [id]);

  /// Number of logged lines that reference the item.
  Future<int> itemUsageCount(String id) async {
    final r = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM meal_entries WHERE item_id = ?',
      [id],
    );
    return r.first['n'] as int;
  }

  Future<int> restoreDefaultItems() => insertDefaultItems(_db);

  // ---- Meals --------------------------------------------------------------

  Future<List<Meal>> meals() async {
    final mealRows = await _db.query('meals', orderBy: 'date, time');
    final entryRows = await _db.query(
      'meal_entries',
      orderBy: 'meal_id, position',
    );
    final byMeal = <String, List<MealEntry>>{};
    for (final r in entryRows) {
      (byMeal[r['meal_id'] as String] ??= []).add(MealEntry.fromRow(r));
    }
    return [
      for (final r in mealRows)
        Meal.fromRow(r, byMeal[r['id'] as String] ?? const []),
    ];
  }

  /// Inserts or replaces a meal and all of its entries atomically.
  Future<void> saveMeal(Meal meal) => _db.transaction((txn) async {
    final now = _now;
    final updated = await txn.update(
      'meals',
      {...meal.toRow(), 'updated_at': now},
      where: 'id = ?',
      whereArgs: [meal.id],
    );
    if (updated == 0) {
      await txn.insert('meals', {
        ...meal.toRow(),
        'created_at': now,
        'updated_at': now,
      });
    }
    await txn.delete(
      'meal_entries',
      where: 'meal_id = ?',
      whereArgs: [meal.id],
    );
    final b = txn.batch();
    for (var i = 0; i < meal.entries.length; i++) {
      b.insert('meal_entries', meal.entries[i].toRow(meal.id, i));
    }
    await b.commit(noResult: true);
  });

  Future<void> deleteMeal(String id) =>
      _db.delete('meals', where: 'id = ?', whereArgs: [id]);

  Future<void> deleteAllMeals() => _db.delete('meals');

  // ---- Settings -----------------------------------------------------------

  Future<Uint8List> snapshot() => _appDb.snapshot();

  Future<void> restore(
    Uint8List bytes, {
    Set<String> keepSettings = const {},
  }) => _appDb.restore(bytes, keepSettings: keepSettings);

  Future<Map<String, String?>> settings() async => {
    for (final r in await _db.query('settings'))
      r['key']! as String: r['value'] as String?,
  };

  Future<String?> setting(String key) async {
    final r = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> setSetting(String key, String? value) => _db.insert('settings', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
