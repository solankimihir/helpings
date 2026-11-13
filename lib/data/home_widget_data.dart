import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../state/app_state.dart';
import 'format.dart';
import 'models.dart';

/// What the Android home-screen widget shows: today's totals.
@immutable
class WidgetPayload {
  const WidgetPayload({
    required this.date,
    required this.calories,
    required this.meals,
    required this.incomplete,
  });

  /// [dayKey] the numbers are for. The widget shows zero once this is no
  /// longer today, until the app next publishes.
  final String date;
  final int calories;
  final int meals;

  /// Some of today's lines have no calories.
  final bool incomplete;

  factory WidgetPayload.of(AppData data, DateTime now) {
    final today = dayKey(now);
    var totals = MealTotals.zero;
    var meals = 0;
    for (final m in data.meals) {
      if (m.date != today) continue;
      meals++;
      totals = totals + m.totals;
    }
    return WidgetPayload(
      date: today,
      calories: totals.sum.round(),
      meals: meals,
      incomplete: totals.missing > 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetPayload &&
      other.date == date &&
      other.calories == calories &&
      other.meals == meals &&
      other.incomplete == incomplete;

  @override
  int get hashCode => Object.hash(date, calories, meals, incomplete);
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
  static const _provider = 'in.mihirsolanki.helpings.HelpingsWidgetProvider';

  bool get _supported => !kIsWeb && Platform.isAndroid;

  @override
  Future<void> publish(WidgetPayload p) async {
    if (!_supported) return;
    await Future.wait([
      HomeWidget.saveWidgetData<String>('date', p.date),
      HomeWidget.saveWidgetData<int>('calories', p.calories),
      HomeWidget.saveWidgetData<int>('meals', p.meals),
      HomeWidget.saveWidgetData<bool>('incomplete', p.incomplete),
    ]);
    await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
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
