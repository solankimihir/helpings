import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

Meal _meal(String id, String date, String food) => Meal(
  id: id,
  type: MealType.lunch,
  date: date,
  time: '12:00',
  entries: [MealEntry(id: '$id-e', nameSnapshot: food)],
);

Future<void> _swipeToEarlierDay(WidgetTester tester) async {
  await tester.fling(find.byType(PageView), const Offset(400, 0), 1500);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('swipe right through earlier days, Today jumps back', (
    tester,
  ) async {
    await pumpApp(
      tester,
      seed: (r) async {
        await r.saveMeal(_meal('t', todayKey(), 'Rice'));
        await r.saveMeal(_meal('y', shiftKey(-1), 'Dal'));
      },
    );
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text(longDate(DateTime.now())), findsOneWidget);
    expect(find.textContaining('Rice'), findsOneWidget);
    expect(find.text('Today'), findsNothing); // no jump pill on today

    // Swiping left on today goes nowhere: there are no future pages.
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('TODAY'), findsOneWidget);

    await _swipeToEarlierDay(tester);
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(find.text(longDate(parseKey(shiftKey(-1)))), findsOneWidget);
    expect(find.textContaining('Dal'), findsOneWidget);
    expect(find.textContaining('Rice'), findsNothing);

    await _swipeToEarlierDay(tester);
    expect(find.text('2 DAYS AGO'), findsOneWidget);
    expect(find.text('Nothing logged'), findsOneWidget);

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.textContaining('Rice'), findsOneWidget);
  });

  testWidgets('adding a meal while viewing a past day uses that day', (
    tester,
  ) async {
    await pumpApp(tester);
    await _swipeToEarlierDay(tester);
    await tester.tap(find.text('+ Add Meal'));
    await tester.pumpAndSettle();
    expect(find.text('Yesterday'), findsOneWidget);
  });

  testWidgets('tapping the date picks any past day', (tester) async {
    final now = DateTime.now();
    // The 1st is always in the month the picker opens on, so no paging.
    // (On the 1st itself this just re-picks today.)
    final target = DateTime(now.year, now.month, 1);
    final key = dayKey(target);
    await pumpApp(tester, seed: (r) => r.saveMeal(_meal('p', key, 'Poha')));

    await tester.tap(find.text(longDate(now)));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.text('${target.day}'),
      ),
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text(longDate(target)), findsOneWidget);
    expect(find.textContaining('Poha'), findsOneWidget);
  });
}
