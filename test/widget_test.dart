import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

void main() {
  testWidgets('home starts empty', (tester) async {
    await pumpApp(tester);
    expect(find.text('Nothing logged yet'), findsOneWidget);
    expect(find.text('nothing logged'), findsOneWidget);
    expect(find.text('+ Add Meal'), findsOneWidget);
  });

  testWidgets('log a meal, view it, then delete it', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('+ Add Meal'));
    await tester.pumpAndSettle();
    expect(find.text('Add Meal'), findsOneWidget);

    // Saving with nothing added shows the design's error.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Add at least one meal item before saving.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Lunch'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Search food — e.g. Roti'),
      'rot',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roti  100', findRichText: true));
    await tester.pumpAndSettle();

    // Pre-filled from the food item's defaults; bump quantity to 2 and
    // calories to 200.
    expect(find.widgetWithText(TextField, '100'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '1'), '2');
    await tester.enterText(find.widgetWithText(TextField, '100'), '200');

    // Add an item with no calories.
    await tester.enterText(
      find.widgetWithText(TextField, 'Search food — e.g. Roti'),
      'samb',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sambar', findRichText: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Home card.
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('2 Roti'), findsOneWidget);
    expect(find.text('1 cup Sambar'), findsOneWidget);
    expect(find.text('200+ kcal'), findsOneWidget);
    expect(find.text('recorded · 1 item without calories'), findsOneWidget);

    // Detail.
    await tester.tap(find.text('2 Roti'));
    await tester.pumpAndSettle();
    expect(find.text('2 Pieces'), findsOneWidget);
    expect(find.text('Not recorded'), findsOneWidget);
    expect(find.text('200 kcal recorded'), findsOneWidget);
    expect(
      find.text('1 item has no calorie value, so this total is incomplete.'),
      findsOneWidget,
    );

    // Two-tap delete.
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm delete'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing logged yet'), findsOneWidget);
  });

  testWidgets('create a new food item from meal search', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('+ Add Meal'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Search food — e.g. Roti'),
      'Paneer',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ Create “Paneer” as a new food item'));
    await tester.pumpAndSettle();
    expect(find.text('Add Meal Item'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'optional').last,
      '260',
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    // Back on the meal sheet with the new row added.
    expect(find.text('Add Meal'), findsOneWidget);
    expect(find.text('Paneer'), findsOneWidget);
    expect(find.widgetWithText(TextField, '260'), findsOneWidget);
  });
}
