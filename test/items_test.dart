import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/seed.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

Finder _search() => find.widgetWithText(TextField, 'Search food items');

void main() {
  testWidgets('meal items: search, create, edit, deactivate, delete', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Meal Items').last);
    await tester.pumpAndSettle();
    expect(find.text('${defaultItems.length} ITEMS'), findsOneWidget);

    // Search narrows the list and offers to create a missing name.
    await tester.enterText(_search(), 'Paneer');
    await tester.pumpAndSettle();
    expect(find.text('0 ITEMS'), findsOneWidget);
    await tester.tap(find.text('+ Create “Paneer”'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('${defaultItems.length + 1} ITEMS'), findsOneWidget);

    // Duplicate names are rejected.
    await tester.tap(find.text('+ New'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'e.g. Roti'), 'roti');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('“Roti” already exists.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Deactivate sinks the item to the bottom and tags it.
    await tester.enterText(_search(), 'Tea');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();
    expect(find.text('Tea  Inactive', findRichText: true), findsOneWidget);
    expect(find.text('Activate'), findsOneWidget);

    // Edit defaults.
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Meal Item'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '90'), '45');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('45 kcal · Cup'), findsOneWidget);

    // Delete.
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete food item'));
    await tester.pumpAndSettle();
    expect(find.text('It isn’t used in any logged meal.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('0 ITEMS'), findsOneWidget);
  });
}
