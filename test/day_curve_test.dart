import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/day_curve.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/state/app_state.dart';

Meal _meal(String id, String date, String time, List<double?> cals) => Meal(
  id: id,
  typeId: 'lunch',
  date: date,
  time: time,
  entries: [
    for (final (i, c) in cals.indexed)
      MealEntry(id: '$id-$i', nameSnapshot: 'Item $i', calories: c),
  ],
);

AppData _data(List<Meal> meals) =>
    AppData(items: const [], meals: meals, defaultUnit: FoodUnit.piece);

const _day = '2026-11-15';

void main() {
  test('a day is a running total in time order, flagging gaps', () {
    final c = curveFor(
      _data([
        _meal('l', _day, '13:15', [500, null]),
        _meal('b', _day, '08:30', [400]),
        _meal('x', '2026-11-14', '09:00', [999]),
      ]),
      _day,
    );
    expect(c.points, const [
      CurvePoint(8 * 60 + 30, 400),
      CurvePoint(13 * 60 + 15, 900, incomplete: true),
    ]);
    expect(c.total, 900);
    expect(c.anyIncomplete, isTrue);
    expect(c.valueAt(8 * 60), 0);
    expect(c.valueAt(8 * 60 + 30), 400);
    expect(c.valueAt(12 * 60), 400);
    expect(c.valueAt(23 * 60), 900);
  });

  test('yesterday and last week are relative to the day shown', () {
    final data = _data([
      _meal('a', '2026-11-14', '09:00', [300]),
      _meal('b', '2026-11-08', '10:00', [700]),
    ]);
    expect(baselineCurve(data, _day, CurveBaseline.yesterday)!.total, 300);
    expect(baselineCurve(data, _day, CurveBaseline.lastWeek)!.total, 700);
    // From the 14th, "yesterday" is the empty 13th.
    expect(baselineCurve(data, '2026-11-14', CurveBaseline.yesterday), isNull);
  });

  test('the average uses the 7 latest logged days and skips empty ones', () {
    final data = _data([
      // Eight logged days, every other day; only the latest seven count.
      for (var i = 1; i <= 8; i++)
        _meal(
          'm$i',
          '2026-11-${(15 - 2 * i).toString().padLeft(2, '0')}',
          '12:00',
          [i == 8 ? 10000 : 700],
        ),
    ]);
    final avg = baselineCurve(data, _day, CurveBaseline.average7)!;
    expect(avg.stepped, isFalse);
    expect(avg.days, 7);
    expect(avg.valueAt(11 * 60), 0);
    expect(avg.valueAt(12 * 60), 700);
    expect(avg.total, 700);
    expect(baselineCurve(_data([]), _day, CurveBaseline.average7), isNull);
  });

  test('average is read between its samples', () {
    final avg = DayCurve(const [
      CurvePoint(0, 0),
      CurvePoint(60, 100),
    ], stepped: false);
    expect(avg.valueAt(30), 50);
    expect(avg.valueAt(90), 100);
  });

  test('range: an hour around the meals, at least 6 AM–9 PM-ish', () {
    expect(curveRange(const DayCurve([]), null), (6 * 60, 21 * 60));
    final early = DayCurve(const [
      CurvePoint(7 * 60 + 40, 300),
      CurvePoint(20 * 60, 900),
    ]);
    expect(curveRange(early, null), (6 * 60, 21 * 60));
    final late = DayCurve(const [CurvePoint(22 * 60 + 30, 300)]);
    expect(curveRange(late, early), (6 * 60, 24 * 60));
    // Now after 9 PM stretches the end.
    expect(
      curveRange(
        const DayCurve([CurvePoint(12 * 60, 1)]),
        null,
        now: 21 * 60 + 10,
      ),
      (11 * 60, 22 * 60),
    );
  });
}
