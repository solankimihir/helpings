import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'seed.dart';

/// Owns the SQLite schema. Bump [version] and extend [_migrate] when the
/// schema changes; never edit an already-shipped step.
class AppDatabase {
  AppDatabase._(this.db, this._factory);

  final Database db;
  final DatabaseFactory _factory;

  static const version = 6;
  static const fileName = 'helpings.db';

  /// Opens (creating on first launch) the on-device database.
  ///
  /// When an existing database is about to be upgraded to a newer schema,
  /// [beforeUpgrade] first gets a copy of it as it is. An error there is
  /// logged and the upgrade goes ahead, so the app still opens.
  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
    Future<void> Function(PendingUpgrade upgrade)? beforeUpgrade,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    if (beforeUpgrade != null) {
      final pending = await _pendingUpgrade(f, dbPath);
      if (pending != null) {
        try {
          await beforeUpgrade(pending);
        } catch (e) {
          debugPrint('Backup before upgrade failed: $e');
        }
      }
    }
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
    return AppDatabase._(db, f);
  }

  /// The database at [path] as it is, if it exists and is older than
  /// [version]. Opened without a version so nothing migrates.
  static Future<PendingUpgrade?> _pendingUpgrade(
    DatabaseFactory f,
    String path,
  ) async {
    if (path == inMemoryDatabasePath || !await f.databaseExists(path)) {
      return null;
    }
    final db = await f.openDatabase(path);
    final int from;
    final Map<String, String?> settings;
    try {
      from =
          (await db.rawQuery('PRAGMA user_version')).first.values.first as int;
      if (from < 1 || from >= version) return null;
      settings = {
        for (final r in await db.query('settings'))
          r['key']! as String: r['value'] as String?,
      };
      // Fold WAL writes into the main file so the copy is complete.
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } finally {
      await db.close();
    }
    final bytes = await File(path).readAsBytes();
    if (!isSqliteFile(bytes)) return null;
    return PendingUpgrade(from: from, bytes: bytes, settings: settings);
  }

  /// A self-contained copy of the database file, suitable for a backup.
  ///
  /// Some devices open SQLite in WAL mode, where recent writes live only in
  /// the `-wal` sidecar. Checkpointing folds them into the main file first
  /// (a no-op in rollback-journal mode).
  /// Throws [StateError] for an in-memory database.
  Future<Uint8List> snapshot() async {
    final path = db.path;
    if (path == inMemoryDatabasePath) {
      throw StateError('Cannot snapshot an in-memory database');
    }
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    final bytes = await File(path).readAsBytes();
    if (!isSqliteFile(bytes)) {
      throw StateError('Database file is not a valid SQLite file');
    }
    return bytes;
  }

  /// Whether [bytes] begin with the SQLite 3 file header.
  static bool isSqliteFile(List<int> bytes) {
    const header = 'SQLite format 3\u0000';
    if (bytes.length < 100) return false;
    for (var i = 0; i < header.length; i++) {
      if (bytes[i] != header.codeUnitAt(i)) return false;
    }
    return true;
  }

  /// User tables, parents before children.
  static const _tables = [
    'units',
    'food_items',
    'meal_types',
    'meals',
    'meal_entries',
    'combos',
    'combo_items',
    'settings',
  ];

  /// Tables every Helpings backup has, back to schema v1. Later tables are
  /// created when the backup is migrated.
  static const _v1Tables = ['food_items', 'meals', 'meal_entries', 'settings'];

  /// Replaces every row with the contents of the backup [bytes], in a single
  /// transaction: on any failure the current data is left untouched.
  ///
  /// Backups from older schema versions are migrated first. Settings whose
  /// keys are in [keepSettings] (device-specific ones) keep their current
  /// values. Throws [BackupFormatException] if [bytes] isn't a Helpings
  /// backup this version can read.
  Future<void> restore(
    Uint8List bytes, {
    Set<String> keepSettings = const {},
  }) async {
    if (!isSqliteFile(bytes)) {
      throw const BackupFormatException("This file isn't a Helpings backup.");
    }
    final dir = db.path == inMemoryDatabasePath
        ? Directory.systemTemp.path
        : p.dirname(db.path);
    final tmp = p.join(dir, 'restore-incoming.db');
    await _factory.deleteDatabase(tmp);
    await File(tmp).writeAsBytes(bytes, flush: true);
    try {
      await _checkBackup(tmp);
      // Bring older backups up to the current schema.
      await (await AppDatabase.open(factory: _factory, path: tmp)).close();

      await db.execute('ATTACH DATABASE ? AS incoming', [tmp]);
      try {
        await db.transaction((txn) async {
          // Checked at commit, so rows can be copied in any order.
          await txn.execute('PRAGMA defer_foreign_keys = ON');
          final keep = keepSettings.toList();
          final notKept = keep.isEmpty
              ? ''
              : ' WHERE key NOT IN (${List.filled(keep.length, '?').join(',')})';
          for (final t in _tables.reversed) {
            await txn.execute(
              'DELETE FROM main.$t${t == 'settings' ? notKept : ''}',
              t == 'settings' ? keep : null,
            );
          }
          for (final t in _tables) {
            final cols = (await txn.rawQuery('PRAGMA main.table_info($t)'))
                .map((r) => '"${r['name']}"')
                .join(', ');
            await txn.execute(
              'INSERT INTO main.$t ($cols) SELECT $cols FROM incoming.$t'
              '${t == 'settings' ? notKept : ''}',
              t == 'settings' ? keep : null,
            );
          }
        });
      } finally {
        await db.execute('DETACH DATABASE incoming');
      }
    } finally {
      await _factory.deleteDatabase(tmp);
    }
  }

  Future<void> _checkBackup(String path) async {
    final Database bk;
    try {
      bk = await _factory.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true),
      );
    } catch (_) {
      throw const BackupFormatException("This file couldn't be opened.");
    }
    try {
      final v = (await bk.rawQuery('PRAGMA user_version')).first.values.first;
      final names = (await bk.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      )).map((r) => r['name']).toSet();
      if (v is! int || v < 1 || !_v1Tables.every(names.contains)) {
        throw const BackupFormatException("This file isn't a Helpings backup.");
      }
      if (v > version) {
        throw const BackupFormatException(
          'This backup is from a newer version of Helpings. '
          'Update the app, then try again.',
        );
      }
      final ok = (await bk.rawQuery('PRAGMA quick_check')).first.values.first;
      if (ok != 'ok') {
        throw const BackupFormatException('This backup file is damaged.');
      }
    } finally {
      await bk.close();
    }
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
    if (from < 2) {
      await db.execute('''
        CREATE TABLE meal_types (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL COLLATE NOCASE UNIQUE,
          position INTEGER NOT NULL,
          active INTEGER NOT NULL DEFAULT 1,
          start_minute INTEGER,
          created_at INTEGER NOT NULL
        )''');
      await insertDefaultMealTypes(db);
      // v1 only ever wrote the five built-in ids; this is a safety net.
      await db.execute(
        "UPDATE meals SET type = 'other' "
        'WHERE type NOT IN (SELECT id FROM meal_types)',
      );
    }
    if (from < 3) {
      await db.execute('''
        CREATE TABLE combos (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL COLLATE NOCASE UNIQUE,
          position INTEGER NOT NULL,
          created_at INTEGER NOT NULL
        )''');
      await db.execute('''
        CREATE TABLE combo_items (
          id TEXT PRIMARY KEY,
          combo_id TEXT NOT NULL REFERENCES combos(id) ON DELETE CASCADE,
          item_id TEXT REFERENCES food_items(id) ON DELETE SET NULL,
          name_snapshot TEXT NOT NULL,
          qty REAL,
          unit TEXT,
          calories REAL,
          position INTEGER NOT NULL
        )''');
      await db.execute(
        'CREATE INDEX idx_combo_items_combo ON combo_items(combo_id)',
      );
    }
    if (from < 4) {
      // Reminder time, minutes after midnight; null = no reminder.
      await db.execute(
        'ALTER TABLE meal_types ADD COLUMN remind_minute INTEGER',
      );
    }
    if (from < 5) {
      // Combo lines take calories from the food list when added to a meal;
      // the column stays but is no longer used.
      await db.execute('UPDATE combo_items SET calories = NULL');
    }
    if (from < 6) {
      // Units move from code into the database so people can add their own.
      await db.execute('''
        CREATE TABLE units (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL COLLATE NOCASE UNIQUE,
          position INTEGER NOT NULL,
          active INTEGER NOT NULL DEFAULT 1,
          created_at INTEGER NOT NULL
        )''');
      await insertDefaultUnits(db);
    }
  }

  Future<void> close() => db.close();
}

/// A file offered for restore that can't be used. [message] is user-facing.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A database about to be upgraded from schema [from] to [AppDatabase.version].
class PendingUpgrade {
  const PendingUpgrade({
    required this.from,
    required this.bytes,
    required this.settings,
  });
  final int from;

  /// The whole database file before the upgrade.
  final Uint8List bytes;

  /// Its settings rows, e.g. the backup folder.
  final Map<String, String?> settings;
}
