import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/cycles.dart';

/// [n] consecutive day keys from [start].
List<String> run(String start, int n) => [
  for (var i = 0; i < n; i++) ordinalKey(dayOrdinal(start) + i),
];

void main() {
  test('day keys round-trip through ordinals, across DST and years', () {
    for (final k in ['2026-03-29', '2026-10-25', '2026-12-31', '2028-02-29']) {
      expect(ordinalKey(dayOrdinal(k)), k);
    }
    expect(dayOrdinal('2027-01-01') - dayOrdinal('2026-12-31'), 1);
  });

  group('periodsFrom', () {
    test('groups runs of days, oldest first', () {
      final p = periodsFrom([...run('2026-10-03', 5), ...run('2026-09-05', 4)]);
      expect(p, [
        const Period('2026-09-05', '2026-09-08'),
        const Period('2026-10-03', '2026-10-07'),
      ]);
      expect(p.last.length, 5);
    });

    test('one forgotten day does not split a period; two do', () {
      expect(periodsFrom(['2026-10-01', '2026-10-03']), [
        const Period('2026-10-01', '2026-10-03'),
      ]);
      expect(periodsFrom(['2026-10-01', '2026-10-04']).length, 2);
    });

    test('nothing logged, nothing back', () {
      expect(periodsFrom(const []), isEmpty);
    });
  });

  group('CycleStats', () {
    test('needs two period starts', () {
      expect(CycleStats.from(periodsFrom(run('2026-10-01', 5))), isNull);
    });

    test('averages cycle and period length', () {
      final s = CycleStats.from(
        periodsFrom([
          ...run('2026-08-01', 4), // 28 days to the next
          ...run('2026-08-29', 6), // 30
          ...run('2026-09-28', 5),
        ]),
      )!;
      expect(s.cycleLength, 29);
      expect(s.periodLength, 5);
      expect(s.cycles, 2);
    });

    test('leaves out implausible cycles (a missed month)', () {
      final s = CycleStats.from(
        periodsFrom([
          ...run('2026-06-01', 5),
          ...run('2026-06-29', 5), // 28
          ...run('2026-08-30', 5), // 62: a month not logged
          ...run('2026-09-27', 5), // 28
        ]),
      )!;
      expect(s.cycleLength, 28);
      expect(s.cycles, 2);
    });

    test('uses only the most recent cycles', () {
      final days = <String>[];
      var start = dayOrdinal('2025-01-01');
      // Eight 40-day cycles, then six 25-day ones.
      for (final gap in [...List.filled(8, 40), ...List.filled(6, 25)]) {
        days.addAll(run(ordinalKey(start), 4));
        start += gap;
      }
      days.addAll(run(ordinalKey(start), 4));
      expect(CycleStats.from(periodsFrom(days))!.cycleLength, 25);
    });
  });

  group('CycleStatus', () {
    final periods = periodsFrom([
      ...run('2026-09-01', 5),
      ...run('2026-09-29', 5),
    ]);
    final stats = CycleStats.from(periods); // 28-day cycle, 5-day period

    test('during a period: period day and cycle day agree', () {
      final st = CycleStatus.on('2026-09-30', periods, stats);
      expect(st.onPeriod, isTrue);
      expect(st.periodDay, 2);
      expect(st.cycleDay, 2);
    });

    test('between periods: cycle day and the estimated next start', () {
      final st = CycleStatus.on('2026-10-10', periods, stats);
      expect(st.onPeriod, isFalse);
      expect(st.cycleDay, 12);
      expect(st.nextStart, '2026-10-27');
      expect(st.nextPredicted, isTrue);
      expect(st.daysUntilNext('2026-10-10'), 17);
    });

    test('late: the estimate is in the past', () {
      final st = CycleStatus.on('2026-10-30', periods, stats);
      expect(st.daysUntilNext('2026-10-30'), -3);
    });

    test('a past day points at the next logged period, not an estimate', () {
      final st = CycleStatus.on('2026-09-15', periods, stats);
      expect(st.cycleDay, 15);
      expect(st.nextStart, '2026-09-29');
      expect(st.nextPredicted, isFalse);
    });

    test('before anything was logged', () {
      final st = CycleStatus.on('2026-08-01', periods, stats);
      expect(st.cycleDay, isNull);
      expect(st.nextStart, '2026-09-01');
    });

    test('one period only: cycle day but no estimate', () {
      final one = periodsFrom(run('2026-10-01', 4));
      final st = CycleStatus.on('2026-10-10', one, CycleStats.from(one));
      expect(st.cycleDay, 10);
      expect(st.nextStart, isNull);
    });
  });

  group('predictedDays', () {
    final periods = periodsFrom([
      ...run('2026-09-01', 5),
      ...run('2026-09-29', 5),
    ]);
    final stats = CycleStats.from(periods);

    test('the next cycles, each the average period length', () {
      final d = predictedDays(periods, stats, '2026-10-10', count: 2);
      expect(d, {...run('2026-10-27', 5), ...run('2026-11-24', 5)});
    });

    test('when late, the estimate starts today', () {
      final d = predictedDays(periods, stats, '2026-10-30', count: 1);
      expect(d, run('2026-10-30', 5).toSet());
    });

    test('none without stats', () {
      final one = periodsFrom(run('2026-10-01', 4));
      expect(predictedDays(one, CycleStats.from(one), '2026-10-10'), isEmpty);
    });
  });
}
