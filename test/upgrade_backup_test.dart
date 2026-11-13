import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/database.dart';
import 'package:helpings/data/repository.dart';
import 'package:helpings/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'schema_fixtures.dart';

void main() {
  late Directory dir;
  setUpAll(sqfliteFfiInit);
  setUp(() => dir = Directory.systemTemp.createTempSync('helpings_upgrade'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// A v5 database file holding one setting, as the v5 app left it.
  Future<String> writeV5({String? folder}) async {
    final path = '${dir.path}/helpings.db';
    final db = await AppDatabase.open(factory: schemaFactory, path: path);
    if (folder != null) {
      await Repository(db).setSetting('auto_backup_folder', folder);
      await Repository(db).setSetting('auto_backup_folder_name', 'Backups');
    }
    await db.db.execute('DROP TABLE units');
    await db.db.setVersion(5);
    await db.close();
    return path;
  }

  test('an upgrade first hands over the old database', () async {
    final path = await writeV5();
    PendingUpgrade? got;
    final db = await AppDatabase.open(
      factory: schemaFactory,
      path: path,
      beforeUpgrade: (u) async => got = u,
    );
    addTearDown(db.close);
    expect(got?.from, 5);
    expect(AppDatabase.isSqliteFile(got!.bytes), isTrue);
    // The copy is the old schema; the live file was upgraded.
    final copy = File('${dir.path}/copy.db')..writeAsBytesSync(got!.bytes);
    final old = await schemaFactory.openDatabase(copy.path);
    expect(await old.getVersion(), 5);
    await old.close();
    expect(await db.db.getVersion(), AppDatabase.version);
  });

  test('no copy for a new or current database', () async {
    var calls = 0;
    final path = '${dir.path}/fresh.db';
    for (var i = 0; i < 2; i++) {
      final db = await AppDatabase.open(
        factory: schemaFactory,
        path: path,
        beforeUpgrade: (_) async => calls++,
      );
      await db.close();
    }
    expect(calls, 0);
  });

  test('a failing backup does not stop the upgrade', () async {
    final path = await writeV5();
    final db = await AppDatabase.open(
      factory: schemaFactory,
      path: path,
      beforeUpgrade: (_) async => throw StateError('disk full'),
    );
    addTearDown(db.close);
    expect(await db.db.getVersion(), AppDatabase.version);
  });

  group('backupBeforeUpgrade', () {
    final at = DateTime(2026, 11, 13, 14, 5);
    const name = 'helpings-before-upgrade-v5-2026-11-13-1405.db';

    Future<PendingUpgrade> pending({String? folder}) async {
      final path = await writeV5(folder: folder);
      late PendingUpgrade u;
      final db = await AppDatabase.open(
        factory: schemaFactory,
        path: path,
        beforeUpgrade: (x) async => u = x,
      );
      await db.close();
      return u;
    }

    test('goes to the chosen backup folder', () async {
      final folder = FakeBackupFolder()..appDir = '${dir.path}/app';
      final where = await backupBeforeUpgrade(
        folder,
        await pending(folder: 'tree://x'),
        at,
      );
      expect(folder.files.keys, [name]);
      expect(where, 'Backups/$name');
      expect(Directory('${dir.path}/app').existsSync(), isFalse);
    });

    test('without a folder, goes to the app folder', () async {
      final folder = FakeBackupFolder()..appDir = '${dir.path}/app';
      final where = await backupBeforeUpgrade(folder, await pending(), at);
      expect(folder.files, isEmpty);
      expect(where, '${dir.path}/app/$name');
      expect(File(where!).existsSync(), isTrue);
    });

    test('falls back to the app folder when the folder is gone', () async {
      final folder = FakeBackupFolder()
        ..appDir = '${dir.path}/app'
        ..lost = true;
      final where = await backupBeforeUpgrade(
        folder,
        await pending(folder: 'tree://x'),
        at,
      );
      expect(where, '${dir.path}/app/$name');
      expect(File(where!).existsSync(), isTrue);
    });
  });
}
