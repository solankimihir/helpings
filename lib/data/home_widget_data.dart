import 'dart:convert' show jsonEncode;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../state/app_state.dart';
import 'format.dart';
import 'models.dart';

/// One row of the Meals widget's list: a meal heading or one of its foods.
/// Pre-formatted here so the native side only lays it out.
@immutable
class WidgetLine {
  const WidgetLine.meal(this.text, this.kcal) : header = true;
  const WidgetLine.item(this.text, this.kcal) : header = false;

  final bool header;
  final String text;

  /// Right-hand calories; empty when unknown.
  final String kcal;

  Map<String, Object> toJson() => {'h': header, 't': text, 'k': kcal};

  @override
  bool operator ==(Object other) =>
      other is WidgetLine &&
      other.header == header &&
      other.text == text &&
      other.kcal == kcal;

  @override
  int get hashCode => Object.hash(header, text, kcal);

  @override
  String toString() => '${header ? '#' : '-'} $text | $kcal';
}

/// What the Android home-screen widgets show: today's totals, and today's
/// meals with their foods.
@immutable
class WidgetPayload {
  const WidgetPayload({
    required this.date,
    required this.calories,
    required this.meals,
    this.items = 0,
    required this.incomplete,
    this.lines = const [],
  });

  /// [dayKey] the numbers are for. The widget shows zero once this is no
  /// longer today, until the app next publishes.
  final String date;
  final int calories;
  final int meals;

  /// Foods across today's meals.
  final int items;

  /// Some of today's lines have no calories.
  final bool incomplete;

  /// Today's meals in time order, each followed by its foods.
  final List<WidgetLine> lines;

  factory WidgetPayload.of(AppData data, DateTime now) {
    final today = dayKey(now);
    final todays = [
      for (final m in data.meals)
        if (m.date == today) m,
    ]..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    var totals = MealTotals.zero;
    final lines = <WidgetLine>[];
    for (final m in todays) {
      final t = m.totals;
      totals = totals + t;
      lines.add(
        WidgetLine.meal(
          '${data.typeName(m)} · ${fmtTime(m.time)}',
          t.count == 0 ? '' : calLabel(t),
        ),
      );
      for (final e in m.entries) {
        lines.add(
          WidgetLine.item(
            lineText(e.nameSnapshot, e.qty, e.unit),
            fmtN(e.calories),
          ),
        );
      }
    }
    return WidgetPayload(
      date: today,
      calories: totals.sum.round(),
      meals: todays.length,
      items: totals.count,
      incomplete: totals.missing > 0,
      lines: lines,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetPayload &&
      other.date == date &&
      other.calories == calories &&
      other.meals == meals &&
      other.items == items &&
      other.incomplete == incomplete &&
      listEquals(other.lines, lines);

  @override
  int get hashCode => Object.hash(
    date,
    calories,
    meals,
    items,
    incomplete,
    Object.hashAll(lines),
  );

  @override
  String toString() =>
      'WidgetPayload($date, $calories kcal, $meals meals, $items items, '
      'incomplete: $incomplete, lines: $lines)';
}

/// The widget's "+ Add meal" button opens the app with this link.
final widgetAddMealUri = Uri.parse('helpings://add-meal');

/// Talks to the home-screen widget. Overridden in tests.
abstract class HomeWidgetBridge {
  Future<void> publish(WidgetPayload payload);

  /// The link a widget tap launched the app with, if any.
  Future<Uri?> launchUri();

  /// Links from widget taps while the app is running.
  Stream<Uri?> get clicks;
}

/// Android only for now; on other platforms every call is a no-op.
class NativeHomeWidgetBridge implements HomeWidgetBridge {
  static const _providers = [
    'in.mihirsolanki.helpings.HelpingsWidgetProvider',
    'in.mihirsolanki.helpings.HelpingsMealsWidgetProvider',
  ];

  bool get _supported => !kIsWeb && Platform.isAndroid;

  @override
  Future<void> publish(WidgetPayload p) async {
    if (!_supported) return;
    await Future.wait([
      HomeWidget.saveWidgetData<String>('date', p.date),
      HomeWidget.saveWidgetData<int>('calories', p.calories),
      HomeWidget.saveWidgetData<int>('meals', p.meals),
      HomeWidget.saveWidgetData<int>('items', p.items),
      HomeWidget.saveWidgetData<bool>('incomplete', p.incomplete),
      HomeWidget.saveWidgetData<String>(
        'lines',
        jsonEncode([for (final l in p.lines) l.toJson()]),
      ),
    ]);
    for (final name in _providers) {
      await HomeWidget.updateWidget(qualifiedAndroidName: name);
    }
  }

  @override
  Future<Uri?> launchUri() async =>
      _supported ? HomeWidget.initiallyLaunchedFromHomeWidget() : null;

  @override
  Stream<Uri?> get clicks =>
      _supported ? HomeWidget.widgetClicked : const Stream.empty();
}

final homeWidgetBridgeProvider = Provider<HomeWidgetBridge>(
  (ref) => NativeHomeWidgetBridge(),
);
