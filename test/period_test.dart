import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/csv_export.dart';
import 'package:helpings/data/cycles.dart';
import 'package:helpings/data/database.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/data/repository.dart';
import 'package:helpings/state/app_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// [n] consecutive day keys starting [ago] days before today.
List<String> daysFrom(int ago, int n) => [
  for (var i = 0; i < n; i++) shiftKey(-ago + i),
];

void main() {
  sqfliteFfiInit();
  final f = databaseFactoryFfiNoIsolate;

  group('storage', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('helpings_period'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('v7 databases gain period_days and keep their health data', () async {
      final path = '${dir.path}/v7.db';
      final db = await AppDatabase.open(factory: f, path: path);
      await Repository(db).saveWeight(
        const WeightEntry(id: 'k', date: '2026-11-16', time: '07:00', kg: 70),
      );
      await db.db.execute('DROP TABLE period_days');
      await db.db.setVersion(7);
      await db.close();

      final up = await AppDatabase.open(factory: f, path: path);
      addTearDown(up.close);
      expect(await up.db.getVersion(), 8);
      final repo = Repository(up);
      expect((await repo.weightEntries()).single.kg, 70);
      expect(await repo.periodDays(), isEmpty);
    });

    test('days are logged once, cleared, and come back sorted', () async {
      final db = await AppDatabase.open(factory: f, path: inMemoryDatabasePath);
      addTearDown(db.close);
      final r = Repository(db);
      await r.setPeriodDays(['2026-11-03', '2026-11-01', '2026-11-02'], true);
      await r.setPeriodDays(['2026-11-02'], true); // already there
      expect(await r.periodDays(), ['2026-11-01', '2026-11-02', '2026-11-03']);
      await r.setPeriodDays(['2026-11-03', '2026-11-09'], false);
      expect(await r.periodDays(), ['2026-11-01', '2026-11-02']);
    });

    test('period days and the setting come back with a backup', () async {
      final src = await AppDatabase.open(factory: f, path: '${dir.path}/a.db');
      final r = Repository(src);
      await r.setPeriodDays(['2026-11-01', '2026-11-02'], true);
      await r.setSetting('track_period', '1');
      final bytes = await src.snapshot();
      await src.close();

      final live = await AppDatabase.open(factory: f, path: '${dir.path}/b.db');
      addTearDown(live.close);
      await live.restore(bytes, keepSettings: deviceSettings);
      final lr = Repository(live);
      expect(await lr.periodDays(), ['2026-11-01', '2026-11-02']);
      expect(await lr.setting('track_period'), '1');
    });
  });

  test('health CSV: one row per period, dated by its first day', () {
    final csv = healthToCsv(
      AppData(
        items: const [],
        meals: const [],
        defaultUnit: FoodUnit.piece,
        periodDays: const {
          '2026-10-02',
          '2026-10-03',
          '2026-10-05', // one forgotten day, same period
          '2026-10-30',
        },
        weight: const [
          WeightEntry(id: 'k', date: '2026-10-30', time: '07:00', kg: 70),
        ],
      ),
    );
    expect(
      csv,
      'Date,Time,Type,Value,Unit,Context,Note\r\n'
      '2026-10-02,,Period,4,days,,\r\n'
      '2026-10-30,,Period,1,days,,\r\n'
      '2026-10-30,07:00,Weight,70,kg,,\r\n',
    );
  });

  group('Health tab', () {
    void tallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Future<Repository> open(
      WidgetTester tester, {
      List<String> days = const [],
    }) async {
      late Repository repo;
      await pumpApp(
        tester,
        seed: (r) async {
          repo = r;
          await r.setSetting('track_period', '1');
          if (days.isNotEmpty) await r.setPeriodDays(days, true);
        },
      );
      await tester.tap(find.text('Health'));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('turning Period on in Settings shows the tab and card', (
      tester,
    ) async {
      tallScreen(tester);
      await pumpApp(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Log your period days'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find
              .ancestor(
                of: find.text('Log your period days'),
                matching: find.byType(Row),
              )
              .first,
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Health'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No periods logged yet'), findsOneWidget);
    });

    testWidgets('"Period started" logs the day; tapping again clears it', (
      tester,
    ) async {
      tallScreen(tester);
      final repo = await open(tester);
      await tester.tap(find.text('Period started'));
      await tester.pumpAndSettle();
      expect(await repo.periodDays(), [todayKey()]);
      expect(find.text('Day 1'), findsOneWidget);
      expect(find.text('of period'), findsOneWidget);
      expect(
        find.text('Log two periods to see when the next is likely.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Logged ✓'));
      await tester.pumpAndSettle();
      expect(await repo.periodDays(), isEmpty);
    });

    testWidgets('two periods give a cycle day and an estimate', (tester) async {
      tallScreen(tester);
      // Started 38 and 10 days ago: a 28-day cycle, next in about 18 days.
      await open(tester, days: [...daysFrom(38, 5), ...daysFrom(10, 5)]);
      expect(find.text('Day 11'), findsOneWidget);
      expect(find.text('of cycle'), findsOneWidget);
      expect(find.textContaining('Next period in about 18 days'), findsOne);
    });

    testWidgets('a late period says so', (tester) async {
      tallScreen(tester);
      // Started 62 and 32 days ago: a 30-day cycle, due 2 days ago.
      await open(tester, days: [...daysFrom(62, 4), ...daysFrom(32, 4)]);
      expect(find.text('Late by 2 days'), findsOneWidget);
    });

    testWidgets('the calendar logs a day and shows history', (tester) async {
      tallScreen(tester);
      final repo = await open(
        tester,
        days: [...daysFrom(38, 5), ...daysFrom(10, 5)],
      );
      await tester.tap(find.text('Calendar & history'));
      await tester.pumpAndSettle();
      expect(find.text('Average cycle'.toUpperCase()), findsOneWidget);
      expect(find.text('Average period'.toUpperCase()), findsOneWidget);
      expect(find.text('History'.toUpperCase()), findsOneWidget);
      expect(find.text('5 days · 28-day cycle'), findsOneWidget);

      final today = DateTime.now();
      await tester.tap(
        find.descendant(
          of: find.byType(GridView),
          matching: find.text('${today.day}'),
        ),
      );
      await tester.pumpAndSettle();
      expect(await repo.periodDays(), contains(todayKey()));
      expect(periodsFrom(await repo.periodDays()).length, 3);
    });
  });
}
