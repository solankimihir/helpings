import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/csv_export.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/state/app_state.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

AppData _data(List<Meal> meals) => AppData(
  items: const [FoodItem(id: 'roti', name: 'Roti (renamed)')],
  meals: meals,
  defaultUnit: FoodUnit.piece,
  mealTypes: const [
    MealType(id: 'lunch', name: 'Office lunch'),
    MealType(id: 'dinner', name: 'Dinner'),
  ],
);

void main() {
  test('one row per line, current names, blanks for missing values', () {
    final csv = mealsToCsv(
      _data([
        const Meal(
          id: 'a',
          typeId: 'lunch',
          date: '2026-11-12',
          time: '13:05',
          entries: [
            MealEntry(
              id: '1',
              itemId: 'roti',
              nameSnapshot: 'Roti',
              qty: 2,
              unit: FoodUnit.piece,
              calories: 200,
            ),
            MealEntry(id: '2', nameSnapshot: 'Sambar', qty: 1.5),
          ],
        ),
      ]),
    );
    expect(csv.split('\r\n'), [
      'Date,Time,Meal type,Item,Quantity,Unit,Calories,Notes',
      '2026-11-12,13:05,Office lunch,Roti (renamed),2,Piece,200,',
      '2026-11-12,13:05,Office lunch,Sambar,1.5,,,',
      '',
    ]);
  });

  test('quotes commas, quotes and newlines; empty meals get one row', () {
    final csv = mealsToCsv(
      _data([
        const Meal(
          id: 'b',
          typeId: 'gone', // a type that no longer exists
          date: '2026-11-13',
          time: '20:00',
          notes: 'Spicy, "extra" chilli\nat Ma\'s',
        ),
      ]),
    );
    expect(
      csv,
      'Date,Time,Meal type,Item,Quantity,Unit,Calories,Notes\r\n'
      '2026-11-13,20:00,Meal,,,,,"Spicy, ""extra"" chilli\nat Ma\'s"\r\n',
    );
  });

  test('bytes start with a UTF-8 byte-order mark', () {
    final bytes = csvBytes('Item\r\nPoha ₹\r\n');
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    expect(utf8.decode(bytes.skip(3).toList()), 'Item\r\nPoha ₹\r\n');
    expect(csvFileName(DateTime(2026, 11, 3)), 'helpings-meals-2026-11-03.csv');
  });

  testWidgets('settings: export hands the CSV to the save dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? name;
    Uint8List? bytes;
    await pumpApp(
      tester,
      seed: (r) => r.saveMeal(
        Meal(
          id: 'm',
          typeId: 'lunch',
          date: todayKey(),
          time: '12:00',
          entries: const [MealEntry(id: 'e', nameSnapshot: 'Dal')],
        ),
      ),
      overrides: [
        csvSaverProvider.overrideWithValue((n, b) async {
          name = n;
          bytes = b;
          return true;
        }),
      ],
    );
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export meals (CSV)'));
    await tester.pump();

    expect(name, csvFileName(DateTime.now()));
    final text = utf8.decode(bytes!.skip(3).toList());
    expect(text, contains(',Lunch,Dal,'));
    expect(find.text('Exported 1 meal.'), findsOneWidget);
  });
}
