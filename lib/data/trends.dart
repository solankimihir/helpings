import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../state/app_state.dart';
import 'format.dart';
import 'models.dart';

enum TrendRange { week, month }

@immutable
class DayTotal {
  const DayTotal({
    required this.date,
    this.calories = 0,
    this.meals = 0,
    this.missing = 0,
  });

  /// [dayKey].
  final String date;

  /// Sum of the calories that were entered.
  final double calories;
  final int meals;

  /// Logged lines without calories: the day's total is a lower bound.
  final int missing;

  bool get logged => meals > 0;
  bool get incomplete => missing > 0;
}

@immutable
class TrendSummary {
  const TrendSummary({
    required this.range,
    required this.label,
    required this.days,
    required this.topFoods,
  });

  final TrendRange range;

  /// "Nov 9 – 15", "November 2026".
  final String label;

  /// Every day in the period, in order (including empty and future ones).
  final List<DayTotal> days;

  /// Most-logged foods in the period, by number of lines, at most five.
  final List<(String, int)> topFoods;

  Iterable<DayTotal> get loggedDays => days.where((d) => d.logged);

  int get mealCount => days.fold(0, (n, d) => n + d.meals);

  /// Average over days with at least one meal; empty days don't drag it
  /// down. Null when nothing was logged.
  double? get averagePerLoggedDay {
    final logged = loggedDays.toList();
    if (logged.isEmpty) return null;
    return logged.fold<double>(0, (s, d) => s + d.calories) / logged.length;
  }

  double get maxCalories =>
      days.fold<double>(0, (m, d) => d.calories > m ? d.calories : m);
}

/// The period [offset] steps back from the one containing [now]
/// (0 = this week / this month). Weeks run Monday to Sunday.
TrendSummary summarizeTrends(
  AppData data,
  TrendRange range,
  int offset,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final DateTime start;
  final int length;
  final String label;
  if (range == TrendRange.week) {
    final monday = today.subtract(Duration(days: today.weekday - 1));
    start = DateTime(monday.year, monday.month, monday.day - 7 * offset);
    length = 7;
    final end = DateTime(start.year, start.month, start.day + 6);
    final md = DateFormat('MMM d', 'en_US');
    label = start.month == end.month
        ? '${md.format(start)} – ${end.day}'
        : '${md.format(start)} – ${md.format(end)}';
  } else {
    start = DateTime(today.year, today.month - offset, 1);
    length = DateTime(start.year, start.month + 1, 0).day;
    label = DateFormat('MMMM y', 'en_US').format(start);
  }

  final keys = [
    for (var i = 0; i < length; i++)
      dayKey(DateTime(start.year, start.month, start.day + i)),
  ];
  final inRange = keys.toSet();
  final byDay = <String, List<Meal>>{};
  final foodCounts = <String, int>{};
  for (final m in data.meals) {
    if (!inRange.contains(m.date)) continue;
    (byDay[m.date] ??= []).add(m);
    for (final e in m.entries) {
      final name = data.displayName(e);
      foodCounts[name] = (foodCounts[name] ?? 0) + 1;
    }
  }

  final days = [
    for (final k in keys)
      () {
        var t = MealTotals.zero;
        final meals = byDay[k] ?? const <Meal>[];
        for (final m in meals) {
          t = t + m.totals;
        }
        return DayTotal(
          date: k,
          calories: t.sum,
          meals: meals.length,
          missing: t.missing,
        );
      }(),
  ];

  final top = foodCounts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0
          ? byCount
          : a.key.toLowerCase().compareTo(b.key.toLowerCase());
    });

  return TrendSummary(
    range: range,
    label: label,
    days: days,
    topFoods: [for (final e in top.take(5)) (e.key, e.value)],
  );
}
