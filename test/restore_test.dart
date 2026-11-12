import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/backup.dart';
import 'package:helpings/data/backup_folder.dart';
import 'package:helpings/data/database.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/data/repository.dart';
import 'package:helpings/state/app_state.dart';
import 'package:helpings/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

Meal _meal(String id, String food) => Meal(
  id: id,
  type: MealType.lunch,
  date: todayKey(),
  time: '12:00',
  entries: [MealEntry(id: '$id-e', nameSnapshot: food)],
);

void main() {
  late Directory dir;
  final f = databaseFactoryFfiNoIsolate;
  setUpAll(sqfliteFfiInit);
  setUp(() => dir = Directory.systemTemp.createTempSync('helpings_restore'));

  /// Every Settings card on screen at once, clear of the floating tab bar.
  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  tearDown(() => dir.deleteSync(recursive: true));

  Future<AppDatabase> openAt(String name) =>
      AppDatabase.open(factory: f, path: '${dir.path}/$name');

  /// A backup containing one meal of [food] and dark theme.
  Future<Uint8List> backupWith(String food) async {
    final src = await openAt('src-$food.db');
    final r = Repository(src);
    await r.saveMeal(_meal('src', food));
    await r.setSetting('theme_mode', 'dark');
    await r.setSetting('last_backup_at', '2020-01-01T00:00:00.000');
    final bytes = await src.snapshot();
    await src.close();
    return bytes;
  }

  group('AppDatabase.restore', () {
    test('replaces data but keeps device settings', () async {
      final bytes = await backupWith('Dal');
      final db = await openAt('live.db');
      addTearDown(db.close);
      final r = Repository(db);
      await r.saveMeal(_meal('live', 'Rice'));
      await r.setSetting('last_backup_at', '2026-11-12T10:00:00.000');

      await db.restore(bytes, keepSettings: deviceSettings);

      final meals = await r.meals();
      expect(meals.map((m) => m.entries.single.nameSnapshot), ['Dal']);
      expect(await r.setting('theme_mode'), 'dark');
      expect(await r.setting('last_backup_at'), '2026-11-12T10:00:00.000');
      expect(File('${dir.path}/restore-incoming.db').existsSync(), isFalse);
    });

    Future<void> expectRejected(Uint8List bytes, String message) async {
      final db = await openAt('live.db');
      addTearDown(db.close);
      final r = Repository(db);
      await r.saveMeal(_meal('live', 'Rice'));
      await expectLater(
        db.restore(bytes),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.message,
            'message',
            contains(message),
          ),
        ),
      );
      expect((await r.meals()).single.entries.single.nameSnapshot, 'Rice');
    }

    test('rejects a file that is not SQLite', () async {
      await expectRejected(
        Uint8List.fromList(List.filled(200, 7)),
        "isn't a Helpings backup",
      );
    });

    test('rejects an unrelated SQLite database', () async {
      final other = await f.openDatabase('${dir.path}/other.db');
      await other.execute('CREATE TABLE notes (id INTEGER)');
      await other.setVersion(1);
      await other.close();
      await expectRejected(
        File('${dir.path}/other.db').readAsBytesSync(),
        "isn't a Helpings backup",
      );
    });

    test('rejects a backup from a newer app version', () async {
      final src = await openAt('newer.db');
      await src.db.setVersion(AppDatabase.version + 1);
      final bytes = await src.snapshot();
      await src.close();
      await expectRejected(bytes, 'newer version');
    });
  });

  test('pruning keeps the newest 30 automatic backups only', () {
    final start = DateTime(2026, 10, 1);
    final auto = [
      for (var i = 0; i < 35; i++)
        autoBackupFileName(start.add(Duration(days: i))),
    ];
    final names = [
      ...auto.reversed,
      'helpings-backup-2026-09-01-1200.db',
      'helpings-before-restore-2026-09-01-1200.db',
      'notes.txt',
    ];
    expect(autoBackupsToPrune(names), unorderedEquals(auto.take(5)));
  });

  group('daily backup', () {
    Future<(FakeBackupFolder, ProviderContainer)> pumpWithFolder(
      WidgetTester tester, {
      Map<String, Uint8List> files = const {},
      String? lastDay,
    }) async {
      final folder = FakeBackupFolder(files: files);
      await tester.runAsync(
        () => pumpApp(
          tester,
          path: '${dir.path}/live.db',
          seed: (r) async {
            await r.saveMeal(_meal('live', 'Rice'));
            await r.setSetting('auto_backup_folder', 'tok');
            await r.setSetting('auto_backup_folder_name', 'Backups');
            if (lastDay != null) {
              await r.setSetting('auto_backup_last_day', lastDay);
            }
          },
          overrides: [backupFolderProvider.overrideWithValue(folder)],
        ),
      );
      await settle(tester);
      return (
        folder,
        ProviderScope.containerOf(tester.element(find.byType(Shell))),
      );
    }

    testWidgets('first open of the day backs up and prunes', (tester) async {
      tallScreen(tester);
      final old = {
        for (var i = 1; i <= 30; i++)
          autoBackupFileName(DateTime.now().subtract(Duration(days: i))):
              Uint8List(0),
        'helpings-backup-2020-01-01-0000.db': Uint8List(0),
      };
      final (folder, container) = await pumpWithFolder(tester, files: old);

      final today = autoBackupFileName(DateTime.now());
      expect(AppDatabase.isSqliteFile(folder.files[today]!), isTrue);
      expect(
        folder.files.keys.where((n) => n.startsWith('helpings-auto-')),
        hasLength(30),
      );
      expect(
        folder.files,
        isNot(
          contains(
            autoBackupFileName(
              DateTime.now().subtract(const Duration(days: 30)),
            ),
          ),
        ),
      );
      expect(folder.files, contains('helpings-backup-2020-01-01-0000.db'));
      expect(
        container.read(appDataProvider).requireValue.autoBackup!.lastDay,
        todayKey(),
      );

      // Coming back to the app the same day doesn't back up again.
      backgroundAndReturn(tester);
      await settle(tester);
      expect(folder.writes, 1);

      // The next day does.
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await tester.runAsync(
        () => container
            .read(appDataProvider.notifier)
            .runAutoBackupIfDue(tomorrow),
      );
      expect(folder.files, contains(autoBackupFileName(tomorrow)));
      expect(folder.writes, 2);
    });

    testWidgets('lost folder access is shown and retried', (tester) async {
      tallScreen(tester);
      final folder = FakeBackupFolder()..lost = true;
      await tester.runAsync(
        () => pumpApp(
          tester,
          path: '${dir.path}/live.db',
          seed: (r) async {
            await r.setSetting('auto_backup_folder', 'tok');
            await r.setSetting('auto_backup_folder_name', 'Backups');
          },
          overrides: [backupFolderProvider.overrideWithValue(folder)],
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Settings'));
      await settle(tester);
      expect(find.text('Folder access lost.'), findsOneWidget);

      folder.lost = false;
      backgroundAndReturn(tester);
      await settle(tester);
      expect(find.text('Folder access lost.'), findsNothing);
      expect(find.text('“Backups” · last backup today'), findsOneWidget);
    });

    testWidgets('choosing a folder backs up now; turning off releases it', (
      tester,
    ) async {
      tallScreen(tester);
      final folder = FakeBackupFolder(
        pickResult: const PickedFolder(token: 'new', name: 'Drive backups'),
      );
      await tester.runAsync(
        () => pumpApp(
          tester,
          path: '${dir.path}/live.db',
          overrides: [backupFolderProvider.overrideWithValue(folder)],
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Settings'));
      await settle(tester);
      await tester.tap(find.text('Choose folder'));
      await settle(tester);
      expect(folder.files, contains(autoBackupFileName(DateTime.now())));
      expect(find.text('“Drive backups” · last backup today'), findsOneWidget);

      await tester.tap(find.text('Turn off daily backup'));
      await settle(tester);
      expect(folder.released, ['new']);
      expect(find.text('Choose folder'), findsOneWidget);
    });
  });

  testWidgets('restore from settings replaces data after confirming', (
    tester,
  ) async {
    tallScreen(tester);
    final bytes = (await tester.runAsync(() => backupWith('Dal')))!;
    final folder = FakeBackupFolder();
    await tester.runAsync(
      () => pumpApp(
        tester,
        path: '${dir.path}/live.db',
        seed: (r) async {
          await r.saveMeal(_meal('live', 'Rice'));
          await r.setSetting('auto_backup_folder', 'tok');
          await r.setSetting('auto_backup_folder_name', 'Backups');
          await r.setSetting('auto_backup_last_day', todayKey());
        },
        overrides: [
          backupFolderProvider.overrideWithValue(folder),
          backupPickerProvider.overrideWithValue(() async => bytes),
        ],
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Settings'));
    await settle(tester);
    await tester.tap(find.text('Restore from a backup…'));
    await settle(tester);
    expect(find.text('Restore this backup?'), findsOneWidget);
    expect(find.textContaining('saved to “Backups” first'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Restore'));
    await settleUntil(tester, find.textContaining('Restored 1 meal'));
    expect(find.textContaining('Restored 1 meal'), findsOneWidget);
    expect(
      folder.files.keys.where((n) => n.startsWith('helpings-before-restore-')),
      hasLength(1),
    );
    // Restored the backup's dark theme (once the theme cross-fade ends).
    await tester.pump(const Duration(seconds: 1));
    expect(
      Theme.of(tester.element(find.text('Settings').first)).brightness,
      Brightness.dark,
    );
  });
}

/// Like [settle], but keeps going (up to ~10s) until [finder] matches, for
/// work whose length isn't known up front. Fails if it never appears.
Future<void> settleUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Leaves the app and comes back, through every lifecycle state in order.
void backgroundAndReturn(WidgetTester tester) {
  for (final s in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

/// Alternates real time (so file I/O completes) with frames (so animations
/// and the futures waiting on them advance), since work here hops between
/// the two.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}
