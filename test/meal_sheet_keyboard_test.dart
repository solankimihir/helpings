import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

void main() {
  testWidgets('search box stays above the keyboard as items are added', (
    tester,
  ) async {
    // A phone-sized screen with the keyboard covering the bottom 300px.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    await tester.tap(find.text('+ Add Meal'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    const keyboardTop = 800 - 300;

    final search = find.widgetWithText(TextField, 'Search food — e.g. Roti');
    for (final (query, item) in [
      ('rot', 'Roti  100'),
      ('dal', 'Dal  180'),
      ('ric', 'Rice  200'),
      ('tea', 'Tea  90'),
      ('cur', 'Curd  90'),
    ]) {
      await tester.enterText(search, query);
      await tester.pumpAndSettle();
      expect(tester.getRect(search).bottom, lessThanOrEqualTo(keyboardTop));
      await tester.tap(find.text(item, findRichText: true));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(search).bottom,
        lessThanOrEqualTo(keyboardTop),
        reason: 'after adding $item',
      );
    }

    // The sheet's header (Save) is still reachable too.
    expect(tester.getRect(find.text('Save')).top, greaterThanOrEqualTo(0));
  });
}
