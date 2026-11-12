import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/data/repository.dart';
import 'package:helpings/data/seed.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

void main() {
  testWidgets('settings: default unit, restore items, delete all meals', (
    tester,
  ) async {
    // Tall enough to show every Settings card at once.
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late Repository repo;
    await pumpApp(
      tester,
      seed: (r) async {
        repo = r;
        await r.saveMeal(
          Meal(
            id: 'm',
            typeId: 'lunch',
            date: todayKey(),
            time: '12:00',
            entries: const [MealEntry(id: 'e', nameSnapshot: 'Dal')],
          ),
        );
      },
    );
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Helpings · ${defaultItems.length} food items · 1 meal stored on device',
      ),
      findsOneWidget,
    );

    // Default unit persists.
    await tester.tap(find.text('Piece'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gram').last);
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => repo.setting('default_unit')), 'gram');

    // Restore when nothing is missing.
    await tester.tap(find.text('Restore default food items'));
    await tester.pump();
    expect(
      find.text('All default food items are already here.'),
      findsOneWidget,
    );

    // Delete all meals.
    await tester.tap(find.text('Delete all meals'));
    await tester.pumpAndSettle();
    expect(find.text('Delete all meals?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete all'));
    await tester.pumpAndSettle();
    expect(find.textContaining('0 meals stored on device'), findsOneWidget);
  });

  testWidgets('settings: appearance overrides and persists', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final db = await pumpApp(tester);
    final repo = Repository(db);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    Brightness brightness() =>
        Theme.of(tester.element(find.text('Appearance'))).brightness;
    expect(brightness(), Brightness.light);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);
    expect(await tester.runAsync(() => repo.setting('theme_mode')), 'dark');

    // System follows the device again.
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
  });
}
