import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'seed.dart';

/// Owns the SQLite schema. Bump [version] and extend [_migrate] when the
/// schema changes; never edit an already-shipped step.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const version = 1;
  static const fileName = 'helpings.db';

  /// Opens (creating on first launch) the on-device database.
  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, v) async {
          await _migrate(db, 0, v);
          await insertDefaultItems(db);
        },
        onUpgrade: _migrate,
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    if (from < 1) {
      final b = db.batch();
      b.execute('''
        CREATE TABLE food_items (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL COLLATE NOCASE UNIQUE,
          default_calories REAL,
          default_unit TEXT,
          active INTEGER NOT NULL DEFAULT 1,
          created_at INTEGER NOT NULL
        )''');
      b.execute('''
        CREATE TABLE meals (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          date TEXT NOT NULL,
          time TEXT NOT NULL,
          notes TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )''');
      b.execute('CREATE INDEX idx_meals_date ON meals(date, time)');
      b.execute('''
        CREATE TABLE meal_entries (
          id TEXT PRIMARY KEY,
          meal_id TEXT NOT NULL REFERENCES meals(id) ON DELETE CASCADE,
          item_id TEXT REFERENCES food_items(id) ON DELETE SET NULL,
          name_snapshot TEXT NOT NULL,
          qty REAL,
          unit TEXT,
          calories REAL,
          position INTEGER NOT NULL
        )''');
      b.execute('CREATE INDEX idx_entries_meal ON meal_entries(meal_id)');
      b.execute('CREATE INDEX idx_entries_item ON meal_entries(item_id)');
      b.execute('''
        CREATE TABLE settings (
          key TEXT PRIMARY KEY,
          value TEXT
        )''');
      await b.commit(noResult: true);
    }
  }

  Future<void> close() => db.close();
}
