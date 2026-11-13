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
/// Logged lines a food's new default calories could update.
class PastLines {
  const PastLines({
    this.fillable = const [],
    this.stale = const [],
    this.other = const [],
    this.otherValues = const [],
    this.otherUnit = 0,
    this.oldCalories,
  });

  /// Lines with no calories that the new default can fill in.
  final List<String> fillable;

  /// Lines that still hold the old default (scaled by quantity).
  final List<String> stale;

  /// Lines with calories that match neither the new nor the old default,
  /// e.g. typed by hand.
  final List<String> other;

  /// The distinct calorie values of [other], ascending.
  final List<double> otherValues;

  /// Lines with no calories in a unit other than the food's default.
  final int otherUnit;

  /// The food's previous default.
  final double? oldCalories;

  bool get isEmpty => fillable.isEmpty && stale.isEmpty && other.isEmpty;
}

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

  /// Logged lines of [after] that a change from [before]'s default calories
  /// could update.
  Future<PastLines> pastLines(FoodItem before, FoodItem after) async {
    // Only a change to the calories or unit is worth asking about.
    if (after.defaultCalories == null ||
        (before.defaultCalories == after.defaultCalories &&
            before.defaultUnit == after.defaultUnit)) {
      return const PastLines();
    }
    final rows = await _db.query(
      'meal_entries',
      columns: ['id', 'qty', 'unit', 'calories'],
      where: 'item_id = ?',
      whereArgs: [after.id],
    );
    final fillable = <String>[];
    final stale = <String>[];
    final other = <String>[];
    final otherValues = <double>{};
    var otherUnit = 0;
    final checkStale =
        before.defaultCalories != null &&
        before.defaultUnit == after.defaultUnit;
    bool same(double a, double b) => (a - b).abs() < 0.001;
    for (final r in rows) {
      final id = r['id'] as String;
      final qty = (r['qty'] as num?)?.toDouble();
      final unit = FoodUnit.tryParse(r['unit'] as String?);
      final cal = (r['calories'] as num?)?.toDouble();
      final next = itemCalories(after, qty, unit);
      if (next == null) {
        if (cal == null) otherUnit++;
      } else if (cal == null) {
        fillable.add(id);
      } else if (!same(cal, next)) {
        final old = checkStale ? itemCalories(before, qty, unit) : null;
        if (old != null && same(cal, old)) {
          stale.add(id);
        } else {
          other.add(id);
          otherValues.add(cal);
        }
      }
    }
    return PastLines(
      fillable: fillable,
      stale: stale,
      other: other,
      otherValues: otherValues.toList()..sort(),
      otherUnit: otherUnit,
      oldCalories: before.defaultCalories,
    );
  }

  /// Sets each of [ids] (lines of [item]) to [item]'s current default,
  /// scaled by the line's quantity. Returns how many changed.
  Future<int> applyPastLines(FoodItem item, Iterable<String> ids) =>
      _db.transaction((txn) async {
        var n = 0;
        for (final id in ids) {
          final rows = await txn.query(
            'meal_entries',
            columns: ['qty', 'unit'],
            where: 'id = ? AND item_id = ?',
            whereArgs: [id, item.id],
          );
          if (rows.isEmpty) continue;
          final cal = itemCalories(
            item,
            (rows.first['qty'] as num?)?.toDouble(),
            FoodUnit.tryParse(rows.first['unit'] as String?),
          );
          if (cal == null) continue;
          n += await txn.update(
            'meal_entries',
            {'calories': cal},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        return n;
      });

  // ---- Meal types ---------------------------------------------------------

  Future<List<MealType>> mealTypes() async {
    final rows = await _db.query('meal_types', orderBy: 'position, name');
    return rows.map(MealType.fromRow).toList();
  }

  /// Inserts (at the end of the list) or updates. Throws
  /// [DuplicateNameException] if another type already uses the name.
  Future<void> saveMealType(MealType type) => _db.transaction((txn) async {
    final clash = await txn.query(
      'meal_types',
      columns: ['name'],
      where: 'name = ? COLLATE NOCASE AND id != ?',
      whereArgs: [type.name, type.id],
      limit: 1,
    );
    if (clash.isNotEmpty) {
      throw DuplicateNameException(clash.first['name'] as String);
    }
    final updated = await txn.update(
      'meal_types',
      {
        'name': type.name,
        'active': type.active ? 1 : 0,
        'start_minute': type.startMinute,
        'remind_minute': type.remindMinute,
      },
      where: 'id = ?',
      whereArgs: [type.id],
    );
    if (updated == 0) {
      final last = await txn.rawQuery(
        'SELECT COALESCE(MAX(position), -1) + 1 AS p FROM meal_types',
      );
      await txn.insert('meal_types', {
        ...type.toRow(),
        'position': last.first['p'] as int,
        'created_at': _now,
      });
    }
  });

  /// Rewrites positions to match [ids], first to last.
  Future<void> reorderMealTypes(List<String> ids) =>
      _db.transaction((txn) async {
        for (var i = 0; i < ids.length; i++) {
          await txn.update(
            'meal_types',
            {'position': i},
            where: 'id = ?',
            whereArgs: [ids[i]],
          );
        }
      });

  Future<int> mealTypeUsageCount(String id) async {
    final r = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM meals WHERE type = ?',
      [id],
    );
    return r.first['n'] as int;
  }

  /// Deletes the type, first moving any meals that use it to [moveTo].
  /// Throws [StateError] if meals use it and [moveTo] is null.
  Future<void> deleteMealType(String id, {String? moveTo}) =>
      _db.transaction((txn) async {
        if (moveTo != null) {
          await txn.update(
            'meals',
            {'type': moveTo},
            where: 'type = ?',
            whereArgs: [id],
          );
        } else {
          final used = await txn.rawQuery(
            'SELECT 1 FROM meals WHERE type = ? LIMIT 1',
            [id],
          );
          if (used.isNotEmpty) {
            throw StateError('Meal type $id is in use; pass moveTo');
          }
        }
        await txn.delete('meal_types', where: 'id = ?', whereArgs: [id]);
      });

  // ---- Combos -------------------------------------------------------------

  Future<List<Combo>> combos() async {
    final rows = await _db.query('combos', orderBy: 'position, name');
    final lines = await _db.query('combo_items', orderBy: 'combo_id, position');
    final byCombo = <String, List<MealEntry>>{};
    for (final r in lines) {
      (byCombo[r['combo_id'] as String] ??= []).add(MealEntry.fromRow(r));
    }
    return [
      for (final r in rows)
        Combo(
          id: r['id'] as String,
          name: r['name'] as String,
          position: r['position'] as int,
          items: byCombo[r['id'] as String] ?? const [],
        ),
    ];
  }

  /// Inserts (at the end) or updates a combo and replaces its lines. Throws
  /// [DuplicateNameException] if another combo already has the name.
  Future<void> saveCombo(Combo combo) => _db.transaction((txn) async {
    final clash = await txn.query(
      'combos',
      columns: ['name'],
      where: 'name = ? COLLATE NOCASE AND id != ?',
      whereArgs: [combo.name, combo.id],
      limit: 1,
    );
    if (clash.isNotEmpty) {
      throw DuplicateNameException(clash.first['name'] as String);
    }
    final updated = await txn.update(
      'combos',
      {'name': combo.name},
      where: 'id = ?',
      whereArgs: [combo.id],
    );
    if (updated == 0) {
      final last = await txn.rawQuery(
        'SELECT COALESCE(MAX(position), -1) + 1 AS p FROM combos',
      );
      await txn.insert('combos', {
        'id': combo.id,
        'name': combo.name,
        'position': last.first['p'] as int,
        'created_at': _now,
      });
    }
    await txn.delete(
      'combo_items',
      where: 'combo_id = ?',
      whereArgs: [combo.id],
    );
    for (var i = 0; i < combo.items.length; i++) {
      // Calories come from the food list when the combo is used.
      final row = combo.items[i].toRow(combo.id, i)
        ..remove('meal_id')
        ..['calories'] = null;
      await txn.insert('combo_items', {...row, 'combo_id': combo.id});
    }
  });

  Future<void> reorderCombos(List<String> ids) => _db.transaction((txn) async {
    for (var i = 0; i < ids.length; i++) {
      await txn.update(
        'combos',
        {'position': i},
        where: 'id = ?',
        whereArgs: [ids[i]],
      );
    }
  });

  Future<void> deleteCombo(String id) =>
      _db.delete('combos', where: 'id = ?', whereArgs: [id]);

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
