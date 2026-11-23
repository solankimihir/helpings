import 'format.dart';

// ---- Period tracking --------------------------------------------------------
// Only days are stored (see `period_days`); periods, cycle lengths and the
// next-period estimate are worked out here. No fertility or ovulation
// estimates, on purpose.

/// Whole days since the epoch for a `YYYY-MM-DD` key; UTC so DST can't skew it.
int dayOrdinal(String key) {
  final d = parseKey(key);
  return DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}

/// The `YYYY-MM-DD` key for a [dayOrdinal].
String ordinalKey(int ordinal) => dayKey(
  DateTime.fromMillisecondsSinceEpoch(
    ordinal * Duration.millisecondsPerDay,
    isUtc: true,
  ),
);

/// Cycles shorter or longer than this (start to start) are left out of the
/// average: usually a missed log rather than a real cycle.
const minCycleDays = 15;
const maxCycleDays = 60;

/// How many recent cycles the averages use.
const statsWindow = 6;

/// A run of logged days. One unlogged day inside a run doesn't split it.
class Period {
  const Period(this.start, this.end);

  final String start;
  final String end;

  int get length => dayOrdinal(end) - dayOrdinal(start) + 1;

  bool contains(String day) {
    final o = dayOrdinal(day);
    return o >= dayOrdinal(start) && o <= dayOrdinal(end);
  }

  @override
  bool operator ==(Object other) =>
      other is Period && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'Period($start–$end)';
}

/// Groups logged [days] into periods, oldest first.
List<Period> periodsFrom(Iterable<String> days) {
  final ords = {for (final d in days) dayOrdinal(d)}.toList()..sort();
  final out = <Period>[];
  int? start, prev;
  for (final o in ords) {
    if (prev != null && o - prev > 2) {
      out.add(Period(ordinalKey(start!), ordinalKey(prev)));
      start = null;
    }
    start ??= o;
    prev = o;
  }
  if (start != null) out.add(Period(ordinalKey(start), ordinalKey(prev!)));
  return out;
}

/// Averages over recent cycles; null until there are two period starts with a
/// usable cycle between them.
class CycleStats {
  const CycleStats({
    required this.cycleLength,
    required this.periodLength,
    required this.cycles,
  });

  /// Average days from one period start to the next, rounded.
  final int cycleLength;

  /// Average period length in days, rounded.
  final int periodLength;

  /// How many cycles the averages are from.
  final int cycles;

  static CycleStats? from(List<Period> periods) {
    if (periods.length < 2) return null;
    final gaps = <int>[
      for (var i = 1; i < periods.length; i++)
        dayOrdinal(periods[i].start) - dayOrdinal(periods[i - 1].start),
    ].where((g) => g >= minCycleDays && g <= maxCycleDays).toList();
    if (gaps.isEmpty) return null;
    final recent = gaps.length > statsWindow
        ? gaps.sublist(gaps.length - statsWindow)
        : gaps;
    final lengths = [
      for (final p
          in periods.length > statsWindow
              ? periods.sublist(periods.length - statsWindow)
              : periods)
        p.length,
    ];
    double avg(List<int> xs) => xs.reduce((a, b) => a + b) / xs.length;
    return CycleStats(
      cycleLength: avg(recent).round(),
      periodLength: avg(lengths).round(),
      cycles: recent.length,
    );
  }
}

/// Where [day] falls in the cycle.
class CycleStatus {
  const CycleStatus({
    this.cycleDay,
    this.periodDay,
    this.nextStart,
    this.nextPredicted = false,
  });

  /// Day of the cycle (1 = first day of the latest period on or before [day]);
  /// null when no period was logged by then.
  final int? cycleDay;

  /// Day of the period when [day] is a logged period day.
  final int? periodDay;

  /// The next period start after [day]: a logged one when there is one,
  /// otherwise the estimate from [CycleStats] (and [nextPredicted] is true).
  final String? nextStart;
  final bool nextPredicted;

  bool get onPeriod => periodDay != null;

  /// Days from the day asked about until [nextStart]; negative when late.
  int? daysUntilNext(String day) =>
      nextStart == null ? null : dayOrdinal(nextStart!) - dayOrdinal(day);

  static CycleStatus on(String day, List<Period> periods, CycleStats? stats) {
    final o = dayOrdinal(day);
    Period? last;
    String? nextLogged;
    for (final p in periods) {
      if (dayOrdinal(p.start) <= o) {
        last = p;
      } else {
        nextLogged = p.start;
        break;
      }
    }
    if (last == null) return CycleStatus(nextStart: nextLogged);
    final cycleDay = o - dayOrdinal(last.start) + 1;
    final periodDay = last.contains(day) ? cycleDay : null;
    if (nextLogged != null) {
      return CycleStatus(
        cycleDay: cycleDay,
        periodDay: periodDay,
        nextStart: nextLogged,
      );
    }
    return CycleStatus(
      cycleDay: cycleDay,
      periodDay: periodDay,
      nextStart: stats == null
          ? null
          : ordinalKey(dayOrdinal(last.start) + stats.cycleLength),
      nextPredicted: stats != null,
    );
  }
}

/// Estimated period days for the next [count] cycles after the last logged
/// period, for the calendar. When the next period is late (its estimated
/// start is before [today]) the estimate moves to start on [today].
Set<String> predictedDays(
  List<Period> periods,
  CycleStats? stats,
  String today, {
  int count = 3,
}) {
  if (stats == null || periods.isEmpty) return const {};
  final lastEnd = dayOrdinal(periods.last.end);
  var start = dayOrdinal(periods.last.start) + stats.cycleLength;
  final t = dayOrdinal(today);
  if (start < t) start = t;
  return {
    for (var k = 0; k < count; k++)
      for (var d = 0; d < stats.periodLength; d++)
        if (start + k * stats.cycleLength + d > lastEnd)
          ordinalKey(start + k * stats.cycleLength + d),
  };
}
