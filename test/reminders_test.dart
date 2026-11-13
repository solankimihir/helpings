import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/database.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/data/reminders.dart';
import 'package:helpings/data/repository.dart';
import 'package:helpings/state/app_state.dart';
import 'package:helpings/ui/meal_sheet.dart';
import 'package:helpings/ui/widgets/common.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'schema_fixtures.dart';

const _types = [
  MealType(id: 'lunch', name: 'Lunch', position: 0, remindMinute: 12 * 60 + 30),
  MealType(id: 'dinner', name: 'Dinner', position: 1, remindMinute: 20 * 60),
  MealType(
    id: 'snack',
    name: 'Snack',
    position: 2,
    active: false, // hidden: never reminded
    remindMinute: 16 * 60,
  ),
  MealType(id: 'other', name: 'Other', position: 3), // no reminder time
];

AppData _data(List<Meal> meals) => AppData(
  items: const [],
  meals: meals,
  defaultUnit: FoodUnit.piece,
  mealTypes: _types,
);

Meal _meal(String id, String type, String date) =>
    Meal(id: id, typeId: type, date: date, time: '12:00');

/// Seeds reminders on, with a lunch reminder at 12:30.
Future<void> _seedReminders(Repository r) async {
  await r.setSetting('reminders_on', '1');
  final lunch = (await r.mealTypes()).firstWhere((t) => t.id == 'lunch');
  await r.saveMealType(lunch.copyWith(remindMinute: () => 12 * 60 + 30));
}

bool _chipSelected(WidgetTester tester, String label) => tester
    .widget<AppChip>(
      find.descendant(
        of: find.byType(MealSheet),
        matching: find.widgetWithText(AppChip, label),
      ),
    )
    .selected;

void main() {
  group('reminderSlots', () {
    // Thursday 1pm: today's lunch reminder (12:30) has already passed.
    final now = DateTime(2026, 11, 12, 13);

    test('next 7 days of visible types with a time, future only', () {
      final slots = reminderSlots(_data([]), now);
      expect(
        slots.first,
        ReminderSlot(
          typeId: 'dinner',
          typeName: 'Dinner',
          at: DateTime(2026, 11, 12, 20),
        ),
      );
      // Today: dinner only. Next 6 days: lunch and dinner.
      expect(slots, hasLength(1 + 6 * 2));
      expect(slots.map((s) => s.typeId).toSet(), {'lunch', 'dinner'});
      expect(slots.last.at, DateTime(2026, 11, 18, 20));
      expect(
        slots.map((s) => s.at).toList(),
        [...slots.map((s) => s.at)]..sort(),
      );
    });

    test('a logged meal skips that day’s reminder for its type', () {
      final slots = reminderSlots(
        _data([
          _meal('a', 'dinner', '2026-11-12'),
          _meal('b', 'lunch', '2026-11-13'),
        ]),
        now,
      );
      expect(slots.where((s) => dayKey(s.at) == '2026-11-12'), isEmpty);
      expect(
        slots.where((s) => dayKey(s.at) == '2026-11-13').map((s) => s.typeId),
        ['dinner'],
      );
    });

    test('nothing when no type has a reminder time', () {
      final untimed = AppData(
        items: const [],
        meals: const [],
        defaultUnit: FoodUnit.piece,
        mealTypes: const [MealType(id: 'x', name: 'X')],
      );
      expect(reminderSlots(untimed, now), isEmpty);
    });
  });

  test('older databases migrate and keep reminder times', () async {
    sqfliteFfiInit();
    final dir = Directory.systemTemp.createTempSync('helpings_rem');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = await AppDatabase.open(
      factory: schemaFactory,
      path: await writeV2('${dir.path}/v2.db'),
    );
    addTearDown(db.close);
    final r = Repository(db);
    expect((await r.mealTypes()).every((t) => t.remindMinute == null), isTrue);
    final lunch = (await r.mealTypes()).firstWhere((t) => t.id == 'lunch');
    await r.saveMealType(lunch.copyWith(remindMinute: () => 750));
    expect(
      (await r.mealTypes()).firstWhere((t) => t.id == 'lunch').remindMinute,
      750,
    );
  });

  group('settings', () {
    Future<FakeReminderScheduler> openSettings(
      WidgetTester tester, {
      bool allow = true,
      bool on = false,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = FakeReminderScheduler(allow: allow);
      await pumpApp(
        tester,
        reminders: fake,
        seed: (r) async {
          final lunch = (await r.mealTypes()).firstWhere(
            (t) => t.id == 'lunch',
          );
          await r.saveMealType(
            lunch.copyWith(remindMinute: () => 23 * 60 + 59),
          );
          if (on) await r.setSetting('reminders_on', '1');
        },
      );
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      return fake;
    }

    Finder reminderSwitch() => find.descendant(
      of: find
          .ancestor(of: find.text('Meal reminders'), matching: find.byType(Row))
          .first,
      matching: find.byType(Switch),
    );

    testWidgets('turning on asks permission, then schedules', (tester) async {
      final fake = await openSettings(tester);
      expect(fake.calls, isEmpty); // off: the plugin isn't touched
      expect(
        find.text('A nudge if a meal isn’t logged by its time'),
        findsOneWidget,
      );

      await tester.tap(reminderSwitch());
      await tester.pumpAndSettle();
      expect(fake.permissionRequests, 1);
      expect(find.text('Lunch 11:59 PM'), findsOneWidget);
      // Today 23:59 may already have passed only in the last minute of the
      // day; either way the next days are scheduled.
      expect(fake.scheduled, isNotEmpty);
      expect(fake.scheduled.every((s) => s.typeId == 'lunch'), isTrue);

      await tester.tap(reminderSwitch());
      await tester.pumpAndSettle();
      expect(fake.scheduled, isEmpty);
    });

    testWidgets('denied permission leaves reminders off', (tester) async {
      final fake = await openSettings(tester, allow: false);
      await tester.tap(reminderSwitch());
      await tester.pump();
      expect(find.textContaining('Notifications are off'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(reminderSwitch()).value, isFalse);
      expect(fake.calls, isEmpty);
    });

    testWidgets('logging a meal drops today’s reminder for it', (tester) async {
      final fake = FakeReminderScheduler();
      // A 23:59 reminder, so today's slot exists for almost the whole day.
      await pumpApp(
        tester,
        reminders: fake,
        seed: (r) async {
          await r.setSetting('reminders_on', '1');
          final lunch = (await r.mealTypes()).firstWhere(
            (t) => t.id == 'lunch',
          );
          await r.saveMealType(
            lunch.copyWith(remindMinute: () => 23 * 60 + 59),
          );
        },
      );
      final hadToday = fake.scheduled.any(
        (s) => s.typeId == 'lunch' && dayKey(s.at) == todayKey(),
      );
      // Only false in the last minute of the day.
      final now = DateTime.now();
      if (now.hour * 60 + now.minute < 23 * 60 + 59) {
        expect(hadToday, isTrue);
      }
      // Save the way the app does, so state reloads and reminders resync.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      await tester.runAsync(
        () => container
            .read(appDataProvider.notifier)
            .saveMeal(_meal('m', 'lunch', todayKey())),
      );
      await tester.pumpAndSettle();
      expect(
        fake.scheduled.where(
          (s) => s.typeId == 'lunch' && dayKey(s.at) == todayKey(),
        ),
        isEmpty,
      );
      if (hadToday) expect(fake.calls.length, greaterThan(1));
    });
  });

  testWidgets('tapping a reminder opens Add Meal for its type', (tester) async {
    final fake = FakeReminderScheduler();
    await pumpApp(tester, reminders: fake, seed: _seedReminders);
    fake.tapHandler!('dinner');
    await tester.pumpAndSettle();
    expect(find.byType(MealSheet), findsOneWidget);
    expect(_chipSelected(tester, 'Dinner'), isTrue);
  });

  testWidgets('a reminder that launched the app opens Add Meal', (
    tester,
  ) async {
    final fake = FakeReminderScheduler(launchedWith: 'snack');
    await pumpApp(tester, reminders: fake, seed: _seedReminders);
    await tester.pumpAndSettle();
    expect(find.byType(MealSheet), findsOneWidget);
    expect(_chipSelected(tester, 'Snack'), isTrue);
  });
}
