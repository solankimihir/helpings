import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

void main() {
  testWidgets('iOS uses Cupertino wheels for unit and time', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpApp(tester);
      await tester.tap(find.text('+ Add Meal'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search food — e.g. Roti'),
        'Dal',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dal  180', findRichText: true));
      await tester.pumpAndSettle();

      // Unit wheel.
      await tester.tap(find.bySemanticsLabel('Unit'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoPicker), findsOneWidget);
      await tester.drag(find.byType(CupertinoPicker), const Offset(0, -40));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoPicker), findsNothing);

      // Time wheel. Adding an item scrolled the sheet down to the search
      // box, so scroll back up to the Time field first.
      await tester.scrollUntilVisible(
        find.bySemanticsLabel('Time'),
        -100,
        scrollable: find
            .ancestor(
              of: find.widgetWithText(TextField, 'Search food — e.g. Roti'),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Time'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('dark mode renders with the dark palette', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpApp(
      tester,
      seed: (r) => r.saveMeal(
        Meal(
          id: 'm',
          typeId: 'dinner',
          date: todayKey(),
          time: '20:00',
          entries: const [
            MealEntry(id: 'e', nameSnapshot: 'Rice', qty: 1, calories: 200),
          ],
        ),
      ),
    );
    final ctx = tester.element(find.text('Dinner'));
    expect(Theme.of(ctx).brightness, Brightness.dark);
    expect(ctx.c.bg, AppColors.dark.bg);
    for (final tab in ['History', 'Meal Items', 'Settings', 'Home']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('1 Rice'));
    await tester.pumpAndSettle();
    expect(find.text('200 kcal'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
