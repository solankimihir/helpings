import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueChanged;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/app.dart';
import 'package:helpings/data/backup_folder.dart';
import 'package:helpings/data/database.dart';
import 'package:helpings/data/home_widget_data.dart';
import 'package:helpings/data/reminders.dart';
import 'package:helpings/data/repository.dart';
import 'package:helpings/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pumps the full app on a fresh in-memory database. Uses the no-isolate FFI
/// factory so SQLite calls complete inside the test's fake async zone.
Future<AppDatabase> pumpApp(
  WidgetTester tester, {
  Future<void> Function(Repository repo)? seed,
  String path = inMemoryDatabasePath,
  List<Override> overrides = const [],
  ReminderScheduler? reminders,
  HomeWidgetBridge? homeWidget,
  bool showAiIntro = false,
}) async {
  sqfliteFfiInit();
  final db = await AppDatabase.open(
    factory: databaseFactoryFfiNoIsolate,
    path: path,
  );
  addTearDown(db.close);
  // Most tests don't want the first-launch walkthrough in the way.
  if (!showAiIntro) await Repository(db).setSetting('ai_intro_seen', '1');
  if (seed != null) await seed(Repository(db));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        // Never touch the real notification plugin in tests.
        reminderSchedulerProvider.overrideWithValue(
          reminders ?? FakeReminderScheduler(),
        ),
        homeWidgetBridgeProvider.overrideWithValue(
          homeWidget ?? FakeHomeWidgetBridge(),
        ),
        ...overrides,
      ],
      child: const HelpingsApp(),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

/// In-memory stand-in for the native backup folder bridge.
class FakeBackupFolder implements BackupFolder {
  FakeBackupFolder({this.files = const {}, this.pickResult});

  Map<String, Uint8List> files;
  PickedFolder? pickResult;

  /// When true every call behaves as if access was revoked.
  bool lost = false;
  int writes = 0;
  final released = <String>[];

  void _check() {
    if (lost) throw const FolderAccessException('Folder access lost.');
  }

  @override
  Future<PickedFolder?> pick() async => pickResult;

  @override
  Future<String> name(String token) async {
    _check();
    return pickResult?.name ?? 'Backups';
  }

  @override
  Future<void> write(String token, String fileName, Uint8List bytes) async {
    _check();
    writes++;
    files = {...files, fileName: bytes};
  }

  @override
  Future<List<String>> list(String token) async {
    _check();
    return files.keys.toList();
  }

  @override
  Future<void> delete(String token, String fileName) async {
    _check();
    files = {...files}..remove(fileName);
  }

  @override
  Future<void> release(String token) async => released.add(token);

  /// Returned by [appFolder]; null means there is none.
  String? appDir;

  @override
  Future<String?> appFolder() async => appDir;
}

/// Records what would have been scheduled.
class FakeReminderScheduler implements ReminderScheduler {
  FakeReminderScheduler({this.allow = true, this.launchedWith});

  /// What the permission prompt answers.
  bool allow;
  String? launchedWith;
  int permissionRequests = 0;

  /// Every call to [replaceAll], in order.
  final calls = <List<ReminderSlot>>[];
  List<ReminderSlot> get scheduled => calls.isEmpty ? const [] : calls.last;

  ValueChanged<String>? tapHandler;

  @override
  set onTap(ValueChanged<String>? handler) => tapHandler = handler;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return allow;
  }

  @override
  Future<void> replaceAll(List<ReminderSlot> slots) async =>
      calls.add(List.of(slots));

  @override
  Future<String?> launchTypeId() async => launchedWith;
}

/// Records what the home-screen widget would have been sent.
class FakeHomeWidgetBridge implements HomeWidgetBridge {
  FakeHomeWidgetBridge({this.launchedWith});

  Uri? launchedWith;
  final published = <WidgetPayload>[];
  final _clicks = StreamController<Uri?>.broadcast();

  void click(Uri uri) => _clicks.add(uri);

  @override
  Future<void> publish(WidgetPayload payload) async => published.add(payload);

  @override
  Future<Uri?> launchUri() async => launchedWith;

  @override
  Stream<Uri?> get clicks => _clicks.stream;
}
