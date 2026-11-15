import 'package:flutter/foundation.dart';

import '../state/app_state.dart';
import 'format.dart';
import 'models.dart';

/// The running calorie total after one meal.
@immutable
class CurvePoint {
  const CurvePoint(this.minute, this.cumulative, {this.incomplete = false});

  /// Minutes after midnight.
  final int minute;
  final double cumulative;

  /// Some of this meal's lines have no calories.
  final bool incomplete;

  @override
  bool operator ==(Object other) =>
      other is CurvePoint &&
      other.minute == minute &&
      other.cumulative == cumulative &&
      other.incomplete == incomplete;

  @override
  int get hashCode => Object.hash(minute, cumulative, incomplete);

  @override
  String toString() =>
      'CurvePoint($minute, $cumulative${incomplete ? ', incomplete' : ''})';
}

/// Calories eaten so far, through one day (or an average of several).
@immutable
class DayCurve {
  const DayCurve(this.points, {this.stepped = true, this.days = 1});

  /// In time order. For a stepped curve, one per meal; otherwise samples.
  final List<CurvePoint> points;

  /// True for a real day: the total jumps at each meal. False for an
  /// average, which is drawn and read as a line through its samples.
  final bool stepped;

  /// How many days went into it.
  final int days;

  bool get isEmpty => points.every((p) => p.cumulative == 0);

  double get total => points.isEmpty ? 0 : points.last.cumulative;

  /// When the first calories (or meal) arrive, or null.
  int? get firstMinute => stepped
      ? points.firstOrNull?.minute
      : points.where((p) => p.cumulative > 0).firstOrNull?.minute;

  /// When the last meal was, or null. For an average, when it stops rising.
  int? get lastMinute {
    if (points.isEmpty) return null;
    if (stepped) return points.last.minute;
    final top = total;
    return points.where((p) => p.cumulative >= top).firstOrNull?.minute;
  }

  bool get anyIncomplete => points.any((p) => p.incomplete);

  /// Calories eaten by [minute].
  double valueAt(int minute) {
    if (stepped) {
      var v = 0.0;
      for (final p in points) {
        if (p.minute > minute) break;
        v = p.cumulative;
      }
      return v;
    }
    if (points.isEmpty || minute <= points.first.minute) {
      return points.firstOrNull?.cumulative ?? 0;
    }
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      if (minute <= b.minute) {
        final f = (minute - a.minute) / (b.minute - a.minute);
        return a.cumulative + (b.cumulative - a.cumulative) * f;
      }
    }
    return points.last.cumulative;
  }
}

int _minuteOf(Meal m) {
  final (h, min) = parseTime(m.time);
  return h * 60 + min;
}

/// [day]'s meals as a running total.
DayCurve curveFor(AppData data, String day) {
  final meals = [
    for (final m in data.meals)
      if (m.date == day) m,
  ]..sort((a, b) => a.sortKey.compareTo(b.sortKey));
  var sum = 0.0;
  return DayCurve([
    for (final m in meals)
      CurvePoint(
        _minuteOf(m),
        sum += m.totals.sum,
        incomplete: m.totals.missing > 0,
      ),
  ]);
}

/// Sample spacing for [CurveBaseline.average7].
const averageStep = 15;

/// What to compare [day] with, relative to [day] itself (so on a past day
/// "yesterday" is the day before it). Null when there's nothing to compare.
DayCurve? baselineCurve(AppData data, String day, CurveBaseline baseline) {
  final d = parseKey(day);
  String back(int n) => dayKey(DateTime(d.year, d.month, d.day - n));
  switch (baseline) {
    case CurveBaseline.yesterday:
    case CurveBaseline.lastWeek:
      final c = curveFor(
        data,
        back(baseline == CurveBaseline.yesterday ? 1 : 7),
      );
      return c.points.isEmpty ? null : c;
    case CurveBaseline.average7:
      final logged = {for (final m in data.meals) m.date};
      final days = <DayCurve>[];
      for (var n = 1; n <= 60 && days.length < 7; n++) {
        final key = back(n);
        if (logged.contains(key)) days.add(curveFor(data, key));
      }
      if (days.isEmpty) return null;
      return DayCurve(
        [
          for (var m = 0; m <= 24 * 60; m += averageStep)
            CurvePoint(
              m,
              days.fold<double>(0, (s, c) => s + c.valueAt(m)) / days.length,
            ),
        ],
        stepped: false,
        days: days.length,
      );
  }
}

/// The X axis, in minutes: from the hour before the first meal of either
/// curve (6 AM if there are none) to the hour after the last, but at least
/// to 9 PM and to [now].
(int, int) curveRange(DayCurve day, DayCurve? base, {int? now}) {
  final firsts = [day.firstMinute, base?.firstMinute].nonNulls;
  final lasts = [day.lastMinute, base?.lastMinute].nonNulls;
  final start = firsts.isEmpty
      ? 6 * 60
      : ((firsts.reduce((a, b) => a < b ? a : b) - 60).clamp(0, 24 * 60) ~/
                60) *
            60;
  var end = 21 * 60;
  for (final m in [...lasts.map((m) => m + 60), ?now]) {
    if (m > end) end = m;
  }
  end = ((end + 59) ~/ 60 * 60).clamp(start + 60, 24 * 60);
  return (start, end);
}
