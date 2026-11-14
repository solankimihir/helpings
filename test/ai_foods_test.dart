import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/backup_folder.dart';
import 'package:helpings/data/clipboard.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/data/repository.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

class FakeClipboard implements ClipboardIO {
  String? text;
  int pastes = 0;

  /// Events in order, to check the backup comes before the paste.
  final List<String> log;
  FakeClipboard(this.log);

  @override
  Future<void> copy(String t) async => text = t;

  @override
  Future<String?> paste() async {
    pastes++;
    log.add('paste');
    return text;
  }
}

/// Records writes in [log] as well.
class LoggingFolder extends FakeBackupFolder {
  LoggingFolder(this.log);
  final List<String> log;

  @override
  Future<void> write(String token, String fileName, bytes) async {
    await super.write(token, fileName, bytes);
    log.add('write $fileName');
  }
}

const _reply = '''
Great, here's the list:

```csv
ID,Food,Unit,Calories per unit,Notes
,Roti,Piece,110,35 g atta
,Sambar,Cup,150,With drumstick
,Masala Dosa,Piece,350,Restaurant size
,Khichdi,Bowl,300,Moong dal
```
''';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('helpings_ai'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
  }

  /// Taps [f], then alternates real waits (for file I/O) with frames (for
  /// dialogs and routes) until the work it started has finished.
  Future<void> tapAndWait(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<(Repository, FakeClipboard, LoggingFolder, List<String>)> start(
    WidgetTester tester, {
    String? folderToken,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final log = <String>[];
    final clip = FakeClipboard(log);
    final folder = LoggingFolder(log)..appDir = '${dir.path}/app';
    final db = await tester.runAsync(
      () => pumpApp(
        tester,
        path: '${dir.path}/helpings.db',
        seed: (r) async {
          if (folderToken != null) {
            await r.setSetting('auto_backup_folder', folderToken);
            await r.setSetting('auto_backup_folder_name', 'Backups');
            await r.setSetting('auto_backup_last_day', todayKey());
          }
          final sambar = (await r.items()).firstWhere(
            (i) => i.name == 'Sambar',
          );
          await r.saveMeal(
            Meal(
              id: 'm',
              typeId: 'lunch',
              date: todayKey(),
              time: '13:00',
              entries: [
                MealEntry(
                  id: 'e',
                  itemId: sambar.id,
                  nameSnapshot: 'Sambar',
                  qty: 2,
                  unit: FoodUnit.cup,
                ),
              ],
            ),
          );
        },
        overrides: [
          clipboardProvider.overrideWithValue(clip),
          backupFolderProvider.overrideWithValue(folder),
        ],
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Meal Items').last);
    await settle(tester);
    await tester.tap(find.text('Ask AI'));
    await settle(tester);
    return (Repository(db!), clip, folder, log);
  }

  testWidgets('copy a prompt, back up to the app folder, review, import, '
      'fill past meals, undo', (tester) async {
    final (repo, clip, _, log) = await start(tester);

    await tester.tap(find.text('Fill in calories'));
    await tester.pump();
    expect(clip.text, contains('ask me short questions'));
    expect(clip.text, contains(',Sambar,Cup,,'));
    await tester.pumpAndSettle();

    clip.text = _reply;
    await tester.tap(find.text('Paste reply'));
    await tester.pumpAndSettle();
    expect(find.text('Back up before importing'), findsOneWidget);
    expect(clip.pastes, 0);

    await tapAndWait(tester, find.text('Use app folder'));
    final backups = Directory('${dir.path}/app').listSync();
    expect(backups.single.path, contains('helpings-before-import-'));
    expect(clip.pastes, 1);

    // Review: additions ticked, the overwrite of Roti's 100 kcal not.
    expect(find.text('Review import'), findsOneWidget);
    expect(find.textContaining('Your data was backed up to'), findsOneWidget);
    expect(find.text('100 kcal / Piece → 110 kcal / Piece'), findsOneWidget);
    expect(find.text('New unit'), findsNothing); // part of a rich text
    expect(find.textContaining('New unit'), findsOneWidget);
    expect(find.text('Import 3 foods'), findsOneWidget);

    await tapAndWait(tester, find.text('Import 3 foods'));
    expect(find.text('Fill in past meals?'), findsOneWidget);
    await tapAndWait(tester, find.text('Fill in'));
    expect(
      find.text('Added 2 foods, updated 1 food, filled in 1 past line'),
      findsOneWidget,
    );

    final items = {
      for (final i in (await tester.runAsync(repo.items))!) i.name: i,
    };
    expect(items['Roti']!.defaultCalories, 100);
    expect(items['Sambar']!.defaultCalories, 150);
    expect(items['Masala Dosa']!.defaultCalories, 350);
    expect(items['Khichdi']!.defaultUnit?.name, 'Bowl');
    final units = (await tester.runAsync(repo.units))!;
    expect(units.last.name, 'Bowl');
    var meal = (await tester.runAsync(repo.meals))!.single;
    expect(meal.entries.single.calories, 300);
    expect(log.indexOf('paste'), greaterThanOrEqualTo(0));

    await tapAndWait(tester, find.text('Undo'));
    final after = {
      for (final i in (await tester.runAsync(repo.items))!) i.name: i,
    };
    expect(after['Sambar']!.defaultCalories, isNull);
    expect(after.containsKey('Masala Dosa'), isFalse);
    expect(after.containsKey('Khichdi'), isFalse);
    meal = (await tester.runAsync(repo.meals))!.single;
    expect(meal.entries.single.calories, isNull);
  });

  testWidgets('with a backup folder set: no question, backup goes there '
      'before the clipboard is read', (tester) async {
    final (_, clip, folder, log) = await start(tester, folderToken: 'tok');
    clip.text = _reply;
    await tapAndWait(tester, find.text('Paste reply'));
    expect(find.text('Back up before importing'), findsNothing);
    final name = folder.files.keys.single;
    expect(name, startsWith('helpings-before-import-'));
    expect(log, ['write $name', 'paste']);
    expect(find.text('Review import'), findsOneWidget);
  });

  testWidgets('cancelling the backup question reads nothing', (tester) async {
    final (_, clip, _, _) = await start(tester);
    clip.text = _reply;
    await tester.tap(find.text('Paste reply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(clip.pastes, 0);
    expect(find.text('Review import'), findsNothing);
  });

  testWidgets('a failed backup stops the import', (tester) async {
    final (_, clip, folder, _) = await start(tester, folderToken: 'tok');
    folder.lost = true;
    clip.text = _reply;
    await tapAndWait(tester, find.text('Paste reply'));
    expect(find.text('Couldn’t back up'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing was imported.'), findsOneWidget);
    expect(clip.pastes, 0);
  });

  testWidgets('choosing a folder in the question turns on daily backup, '
      'then backs up there', (tester) async {
    final (_, clip, folder, _) = await start(tester);
    folder.pickResult = const PickedFolder(token: 'new', name: 'Backups');
    clip.text = _reply;
    await tester.tap(find.text('Paste reply'));
    await tester.pumpAndSettle();
    await tapAndWait(tester, find.text('Choose folder'));
    expect(
      folder.files.keys.where((n) => n.startsWith('helpings-before-import-')),
      hasLength(1),
    );
    expect(find.text('Review import'), findsOneWidget);
  });

  testWidgets('a reply without a food list says so', (tester) async {
    final (_, clip, _, _) = await start(tester, folderToken: 'tok');
    clip.text = 'What do you usually eat for breakfast?';
    await tapAndWait(tester, find.text('Paste reply'));
    expect(find.textContaining('Couldn’t find a food list'), findsOneWidget);
  });

  group('first-launch walkthrough', () {
    testWidgets('shown once, three pages, opens Ask AI', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = await pumpApp(tester, showAiIntro: true);
      await tester.pumpAndSettle();
      expect(find.text('Build your food list with AI'), findsOneWidget);
      expect(await Repository(db).setting('ai_intro_seen'), '1');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Fill in missing calories'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('How it works'), findsOneWidget);
      await tester.tap(find.text('Show me'));
      await tester.pumpAndSettle();
      expect(find.text('Ask an AI'), findsOneWidget);
    });

    testWidgets('not over a widget launch; waits for a normal one', (
      tester,
    ) async {
      final db = await pumpApp(
        tester,
        showAiIntro: true,
        homeWidget: FakeHomeWidgetBridge(
          launchedWith: Uri.parse('helpings://add-meal'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Build your food list with AI'), findsNothing);
      expect(await Repository(db).setting('ai_intro_seen'), isNull);
    });
  });
}
