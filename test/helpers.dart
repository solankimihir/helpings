import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/app.dart';
import 'package:helpings/data/database.dart';
import 'package:helpings/data/repository.dart';
import 'package:helpings/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pumps the full app on a fresh in-memory database. Uses the no-isolate FFI
/// factory so SQLite calls complete inside the test's fake async zone.
Future<AppDatabase> pumpApp(
  WidgetTester tester, {
  Future<void> Function(Repository repo)? seed,
}) async {
  sqfliteFfiInit();
  final db = await AppDatabase.open(
    factory: databaseFactoryFfiNoIsolate,
    path: inMemoryDatabasePath,
  );
  addTearDown(db.close);
  if (seed != null) await seed(Repository(db));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
      child: const HelpingsApp(),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}
