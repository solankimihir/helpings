import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/csv_export.dart';
import 'package:helpings/data/database.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/data/repository.dart';
import 'package:helpings/state/app_state.dart';
import 'package:helpings/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

void main() {
  sqfliteFfiInit();
  final f = databaseFactoryFfiNoIsolate;

  group('storage', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('helpings_health'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('v6 databases gain the health tables and keep their meals', () async {
      final path = '${dir.path}/v6.db';
      final db = await AppDatabase.open(factory: f, path: path);
      await Repository(db).saveMeal(
        Meal(id: 'm', typeId: 'lunch', date: todayKey(), time: '12:00'),
      );
      for (final t in AppDatabase.healthTables) {
        await db.db.execute('DROP TABLE $t');
      }
      await db.db.setVersion(6);
      await db.close();

      final up = await AppDatabase.open(factory: f, path: path);
      addTearDown(up.close);
      expect(await up.db.getVersion(), AppDatabase.version);
      final repo = Repository(up);
      expect((await repo.meals()).single.id, 'm');
      expect(await repo.sugarReadings(), isEmpty);
      expect(await repo.waterEntries(), isEmpty);
      expect(await repo.weightEntries(), isEmpty);
    });

    test('repository round-trips each tracker', () async {
      final db = await AppDatabase.open(factory: f, path: inMemoryDatabasePath);
      addTearDown(db.close);
      final r = Repository(db);
      const s = SugarReading(
        id: 's',
        date: '2026-11-16',
        time: '07:30',
        mgdl: 98,
        context: SugarContext.fasting,
        note: 'Before walk',
      );
      await r.saveSugar(s);
      await r.saveSugar(s.copyWith(mgdl: 101));
      final got = (await r.sugarReadings()).single;
      expect(got.mgdl, 101);
      expect(got.context, SugarContext.fasting);
      expect(got.note, 'Before walk');

      await r.saveWater(
        const WaterEntry(id: 'w1', date: '2026-11-16', time: '09:00', ml: 250),
      );
      await r.saveWater(
        const WaterEntry(id: 'w2', date: '2026-11-16', time: '08:00', ml: 500),
      );
      expect([for (final w in await r.waterEntries()) w.id], ['w2', 'w1']);
      await r.deleteWater('w2');
      expect((await r.waterEntries()).single.id, 'w1');

      await r.saveWeight(
        const WeightEntry(id: 'k', date: '2026-11-16', time: '07:00', kg: 72.4),
      );
      expect((await r.weightEntries()).single.kg, 72.4);
      await r.deleteWeight('k');
      expect(await r.weightEntries(), isEmpty);
    });

    test('health rows and tracker settings come back with a backup', () async {
      final src = await AppDatabase.open(factory: f, path: '${dir.path}/a.db');
      final r = Repository(src);
      await r.saveWater(
        const WaterEntry(id: 'w', date: '2026-11-16', time: '09:00', ml: 300),
      );
      await r.saveWeight(
        const WeightEntry(id: 'k', date: '2026-11-16', time: '07:00', kg: 70),
      );
      await r.setSetting('track_water', '1');
      await r.setSetting('weight_unit', 'lb');
      final bytes = await src.snapshot();
      await src.close();

      final live = await AppDatabase.open(factory: f, path: '${dir.path}/b.db');
      addTearDown(live.close);
      await live.restore(bytes, keepSettings: deviceSettings);
      final lr = Repository(live);
      expect((await lr.waterEntries()).single.ml, 300);
      expect((await lr.weightEntries()).single.kg, 70);
      expect(await lr.setting('track_water'), '1');
      expect(await lr.setting('weight_unit'), 'lb');
    });
  });

  test('health CSV: every tracker in time order, canonical units', () {
    final csv = healthToCsv(
      AppData(
        items: const [],
        meals: const [],
        defaultUnit: FoodUnit.piece,
        sugar: const [
          SugarReading(
            id: 's',
            date: '2026-11-16',
            time: '07:30',
            mgdl: 99.088,
            context: SugarContext.fasting,
            note: 'Felt fine, rested',
          ),
        ],
        water: const [
          WaterEntry(id: 'w', date: '2026-11-16', time: '09:00', ml: 250),
        ],
        weight: const [
          WeightEntry(id: 'k', date: '2026-11-16', time: '07:00', kg: 72.4),
        ],
      ),
    );
    expect(
      csv,
      'Date,Time,Type,Value,Unit,Context,Note\r\n'
      '2026-11-16,07:00,Weight,72.4,kg,,\r\n'
      '2026-11-16,07:30,Blood sugar,99.09,mg/dL,Fasting,"Felt fine, rested"\r\n'
      '2026-11-16,09:00,Water,250,ml,,\r\n',
    );
  });

  group('Health tab', () {
    /// Room for every card and the tab bar.
    void tallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('appears when a tracker is turned on, and goes when off', (
      tester,
    ) async {
      tallScreen(tester);
      await pumpApp(tester);
      expect(find.text('Health'), findsNothing);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final waterSwitch = find.descendant(
        of: find
            .ancestor(of: find.text('Water'), matching: find.byType(Row))
            .first,
        matching: find.byType(Switch),
      );
      await tester.tap(waterSwitch);
      await tester.pumpAndSettle();
      expect(find.text('Health'), findsOneWidget);

      await tester.tap(find.text('Health'));
      await tester.pumpAndSettle();
      expect(find.text('No daily goal set'), findsOneWidget);

      // Turn it off from Settings: the tab goes and Home shows again.
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(waterSwitch);
      await tester.pumpAndSettle();
      expect(find.text('Health'), findsNothing);
    });

    testWidgets('quick-add water, with undo', (tester) async {
      tallScreen(tester);
      late Repository repo;
      await pumpApp(
        tester,
        seed: (r) async {
          repo = r;
          await r.setSetting('track_water', '1');
          await r.setSetting('water_goal_ml', '2000');
        },
      );
      await tester.tap(find.text('Health'));
      await tester.pumpAndSettle();
      expect(find.text('0%'), findsOneWidget);

      await tester.tap(find.text('+500 ml'));
      await tester.pumpAndSettle();
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('1,500 ml to go of 2,000'), findsOneWidget);
      expect(
        (await tester.runAsync(repo.waterEntries))!.single.date,
        todayKey(),
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('0%'), findsOneWidget);
      expect(await tester.runAsync(repo.waterEntries), isEmpty);
    });

    testWidgets('a sugar reading typed in mmol/L is stored as mg/dL', (
      tester,
    ) async {
      tallScreen(tester);
      late Repository repo;
      await pumpApp(
        tester,
        seed: (r) async {
          repo = r;
          await r.setSetting('track_sugar', '1');
          await r.setSetting('sugar_unit', 'mmol');
        },
      );
      await tester.tap(find.text('Health'));
      await tester.pumpAndSettle();
      expect(find.text('No readings on this day.'), findsOneWidget);

      await tester.tap(find.text('+ Add'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '5.5');
      await tester.tap(find.text('After meal'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final s = (await tester.runAsync(repo.sugarReadings))!.single;
      expect(s.mgdl, closeTo(99.09, .01));
      expect(s.context, SugarContext.afterMeal);
      expect(find.text('5.5'), findsOneWidget);
      expect(find.text('After meal'), findsOneWidget);
    });

    testWidgets('weight shows the change since a week before', (tester) async {
      tallScreen(tester);
      await pumpApp(
        tester,
        seed: (r) async {
          await r.setSetting('track_weight', '1');
          await r.saveWeight(
            WeightEntry(id: 'a', date: shiftKey(-7), time: '07:00', kg: 73),
          );
          await r.saveWeight(
            WeightEntry(id: 'b', date: todayKey(), time: '07:00', kg: 72.4),
          );
        },
      );
      await tester.tap(find.text('Health'));
      await tester.pumpAndSettle();
      expect(find.text('72.4'), findsOneWidget);
      expect(find.textContaining('−0.6 kg in 7 days'), findsOneWidget);
    });
  });

  test('the Health tab sits between History and Meal Items', () {
    expect(AppTab.values.indexOf(AppTab.health), 2);
  });
}
