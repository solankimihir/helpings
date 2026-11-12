import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The schema as shipped in v1, before meal types became a table.
const v1Schema = [
  '''CREATE TABLE food_items (id TEXT PRIMARY KEY,
     name TEXT NOT NULL COLLATE NOCASE UNIQUE, default_calories REAL,
     default_unit TEXT, active INTEGER NOT NULL DEFAULT 1,
     created_at INTEGER NOT NULL)''',
  '''CREATE TABLE meals (id TEXT PRIMARY KEY, type TEXT NOT NULL,
     date TEXT NOT NULL, time TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
     created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
  '''CREATE TABLE meal_entries (id TEXT PRIMARY KEY,
     meal_id TEXT NOT NULL REFERENCES meals(id) ON DELETE CASCADE,
     item_id TEXT REFERENCES food_items(id) ON DELETE SET NULL,
     name_snapshot TEXT NOT NULL, qty REAL, unit TEXT, calories REAL,
     position INTEGER NOT NULL)''',
  'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)',
];

final schemaFactory = databaseFactoryFfiNoIsolate;
final _f = schemaFactory;

/// A v1 database file with one 'snack' meal and one with an unknown type.
Future<String> writeV1(String path) async {
  final db = await _f.openDatabase(path);
  for (final sql in v1Schema) {
    await db.execute(sql);
  }
  for (final (id, type) in [('m1', 'snack'), ('m2', 'mystery')]) {
    await db.insert('meals', {
      'id': id,
      'type': type,
      'date': '2026-11-01',
      'time': '16:00',
      'created_at': 0,
      'updated_at': 0,
    });
  }
  await db.setVersion(1);
  await db.close();
  return path;
}

/// [writeV1] upgraded to v2 by hand, as the v2 app would have left it:
/// meal types added, no combos yet.
Future<String> writeV2(String path) async {
  await writeV1(path);
  final db = await _f.openDatabase(path);
  await db.execute(v2MealTypesSql);
  for (final (i, (id, name)) in const [
    ('breakfast', 'Breakfast'),
    ('lunch', 'Lunch'),
    ('dinner', 'Dinner'),
    ('snack', 'Snack'),
    ('other', 'Other'),
  ].indexed) {
    await db.insert('meal_types', {
      'id': id,
      'name': name,
      'position': i,
      'active': 1,
      'created_at': 0,
    });
  }
  await db.execute("UPDATE meals SET type = 'other' WHERE type = 'mystery'");
  await db.setVersion(2);
  await db.close();
  return path;
}

const v2MealTypesSql = '''CREATE TABLE meal_types (id TEXT PRIMARY KEY,
     name TEXT NOT NULL COLLATE NOCASE UNIQUE, position INTEGER NOT NULL,
     active INTEGER NOT NULL DEFAULT 1, start_minute INTEGER,
     created_at INTEGER NOT NULL)''';
