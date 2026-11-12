import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:helpings/data/backup.dart';
import 'package:helpings/data/database.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/data/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

Meal _meal() => Meal(
  id: 'm',
  typeId: 'lunch',
  date: todayKey(),
  time: '12:00',
  entries: const [MealEntry(id: 'e', nameSnapshot: 'Dal')],
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('helpings_backup'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('backup file name', () {
    expect(
      backupFileName(DateTime(2026, 11, 2, 9, 5)),
      'helpings-backup-2026-11-02-0905.db',
    );
  });

  test(
    'snapshot includes WAL writes and reopens as a valid database',
    () async {
      sqfliteFfiInit();
      final f = databaseFactoryFfiNoIsolate;
      final db = await AppDatabase.open(
        factory: f,
        path: '${dir.path}/helpings.db',
      );
      // Match Android, where recent writes sit in the -wal file.
      await db.db.rawQuery('PRAGMA journal_mode = WAL');
      await Repository(db).saveMeal(_meal());

      final bytes = await db.snapshot();
      await db.close();
      expect(AppDatabase.isSqliteFile(bytes), isTrue);

      final copyPath = '${dir.path}/copy.db';
      File(copyPath).writeAsBytesSync(bytes);
      final copy = await AppDatabase.open(factory: f, path: copyPath);
      addTearDown(copy.close);
      final meals = await Repository(copy).meals();
      expect(meals.single.entries.single.nameSnapshot, 'Dal');
    },
  );

  test('in-memory database cannot be snapshotted', () async {
    sqfliteFfiInit();
    final db = await AppDatabase.open(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    addTearDown(db.close);
    expect(db.snapshot, throwsStateError);
  });

  testWidgets('settings: save copy hands the database to the saver', (
    tester,
  ) async {
    // Every Settings card on screen, clear of the floating tab bar.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? savedName;
    Uint8List? savedBytes;
    var accept = false;
    final db = await tester.runAsync(
      () => pumpApp(
        tester,
        path: '${dir.path}/helpings.db',
        seed: (r) => r.saveMeal(_meal()),
        overrides: [
          backupSaverProvider.overrideWithValue((name, bytes) async {
            savedName = name;
            savedBytes = bytes;
            return accept;
          }),
        ],
      ),
    );
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
    }

    await settle();
    await tester.tap(find.text('Settings'));
    await settle();
    expect(find.text('Save a copy of your data to a file'), findsOneWidget);

    // Cancelling the dialog records nothing.
    await tester.runAsync(() async {
      await tester.tap(find.text('Save copy'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(savedName, startsWith('helpings-backup-'));
    expect(AppDatabase.isSqliteFile(savedBytes!), isTrue);
    expect(find.text('Backup saved.'), findsNothing);
    expect(
      await tester.runAsync(() => Repository(db!).setting('last_backup_at')),
      isNull,
    );

    accept = true;
    await tester.runAsync(() async {
      await tester.tap(find.text('Save copy'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.text('Backup saved.'), findsOneWidget);
    expect(find.textContaining('Last saved '), findsOneWidget);
  });
}
