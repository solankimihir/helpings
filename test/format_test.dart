import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';

void main() {
  test('lineText matches the design', () {
    expect(lineText('Idli', 2, FoodUnit.piece), '2 Idli');
    expect(lineText('Dal', 1, FoodUnit.cup), '1 cup Dal');
    expect(lineText('Dal', 2, FoodUnit.cup), '2 cups Dal');
    expect(lineText('Rice', 150, FoodUnit.gram), '150 g Rice');
    expect(lineText('Tea', null, null), 'Tea');
    expect(lineText('Ghee', 1.5, FoodUnit.spoon), '1.5 spoons Ghee');
  });

  test('qtyLabel', () {
    expect(qtyLabel(2, FoodUnit.piece), '2 Pieces');
    expect(qtyLabel(1, FoodUnit.cup), '1 Cup');
    expect(qtyLabel(null, null), '— no unit');
  });

  test('fmtTime', () {
    expect(fmtTime('08:30'), '8:30 AM');
    expect(fmtTime('13:05'), '1:05 PM');
    expect(fmtTime('00:00'), '12:00 AM');
    expect(fmtTime('12:00'), '12:00 PM');
  });

  test('calLabel never estimates', () {
    MealEntry e(double? c) =>
        MealEntry(id: 'x', nameSnapshot: 'x', calories: c);
    expect(calLabel(MealTotals.of([e(120), e(90)])), '210 kcal');
    expect(calLabel(MealTotals.of([e(120), e(null)])), '120+ kcal');
    expect(calLabel(MealTotals.of([e(null)])), 'No calories');
    expect(calLabel(MealTotals.of([])), '—');
    expect(calLabel(MealTotals.of([e(1200), e(300)])), '1,500 kcal');
  });

  test('parseNum is lenient', () {
    expect(parseNum('2'), 2);
    expect(parseNum('1.5'), 1.5);
    expect(parseNum('200 kcal'), 200);
    expect(parseNum(''), isNull);
    expect(parseNum('abc'), isNull);
  });

  test('day helpers', () {
    final now = DateTime(2026, 11, 12, 9);
    expect(todayKey(now), '2026-11-12');
    expect(shiftKey(-12, now), '2026-10-31');
    expect(dayGroupLabel('2026-11-12', now), 'Today');
    expect(dayGroupLabel('2026-11-11', now), 'Yesterday');
    expect(dayGroupLabel('2026-11-03', now), 'November 3');
    expect(dayGroupLabel('2025-12-31', now), 'December 31, 2025');
    expect(longDate(now), 'Thursday, November 12');
  });

  test('meal type guess by hour', () {
    expect(MealType.forHour(8), MealType.breakfast);
    expect(MealType.forHour(13), MealType.lunch);
    expect(MealType.forHour(16), MealType.snack);
    expect(MealType.forHour(20), MealType.dinner);
  });
}
