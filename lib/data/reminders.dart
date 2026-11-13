import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../state/app_state.dart';
import 'format.dart';

/// How far ahead reminders are scheduled. They're one-shot (so a logged
/// meal can skip its own), and refreshed every time the app opens.
const reminderDays = 7;

/// One notification to schedule.
@immutable
class ReminderSlot {
  const ReminderSlot({
    required this.typeId,
    required this.typeName,
    required this.at,
  });

  final String typeId;
  final String typeName;

  /// Local wall-clock time.
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is ReminderSlot &&
      other.typeId == typeId &&
      other.typeName == typeName &&
      other.at == at;

  @override
  int get hashCode => Object.hash(typeId, typeName, at);

  @override
  String toString() => 'ReminderSlot($typeId @ $at)';
}

/// Reminders for the next [reminderDays] days from [now]: one per visible
/// meal type with a reminder time, skipping times already past and days
/// that already have a meal of that type. Sorted by time.
List<ReminderSlot> reminderSlots(AppData data, DateTime now) {
  final logged = {for (final m in data.meals) '${m.date}|${m.typeId}'};
  final slots = <ReminderSlot>[];
  for (var d = 0; d < reminderDays; d++) {
    final day = DateTime(now.year, now.month, now.day + d);
    final key = dayKey(day);
    for (final t in data.visibleTypes) {
      final m = t.remindMinute;
      if (m == null || logged.contains('$key|${t.id}')) continue;
      final at = DateTime(day.year, day.month, day.day, m ~/ 60, m % 60);
      if (!at.isAfter(now)) continue;
      slots.add(ReminderSlot(typeId: t.id, typeName: t.name, at: at));
    }
  }
  return slots..sort((a, b) => a.at.compareTo(b.at));
}

/// Talks to the platform's notification system. Overridden in tests.
abstract class ReminderScheduler {
  /// Asks the user to allow notifications. True if allowed.
  Future<bool> requestPermission();

  /// Replaces every scheduled reminder with [slots] (empty clears them).
  Future<void> replaceAll(List<ReminderSlot> slots);

  /// The meal type id of a reminder that launched the app, if any.
  Future<String?> launchTypeId();

  /// Called with the meal type id when a reminder is tapped while the app
  /// is running.
  set onTap(ValueChanged<String>? handler);
}

class NativeReminderScheduler implements ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;
  ValueChanged<String>? _onTap;

  @override
  set onTap(ValueChanged<String>? handler) => _onTap = handler;

  Future<void> _init() => _ready ??= () async {
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (e) {
      debugPrint('Timezone lookup failed, using UTC offset: $e');
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is asked for explicitly, when reminders are turned on.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final id = r.payload;
        if (id != null && id.isNotEmpty) _onTap?.call(id);
      },
    );
  }();

  @override
  Future<bool> requestPermission() async {
    await _init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'meal_reminders',
      'Meal reminders',
      channelDescription: 'A nudge to log a meal you haven’t logged yet',
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> replaceAll(List<ReminderSlot> slots) async {
    await _init();
    await _plugin.cancelAll();
    for (var i = 0; i < slots.length; i++) {
      final s = slots[i];
      await _plugin.zonedSchedule(
        id: i,
        scheduledDate: tz.TZDateTime(
          tz.local,
          s.at.year,
          s.at.month,
          s.at.day,
          s.at.hour,
          s.at.minute,
        ),
        notificationDetails: _details,
        // Inexact: no exact-alarm permission needed; a few minutes' drift
        // is fine for a nudge.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: 'Logged ${s.typeName.toLowerCase()} yet?',
        body: 'Tap to add it.',
        payload: s.typeId,
      );
    }
  }

  @override
  Future<String?> launchTypeId() async {
    await _init();
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d == null || !d.didNotificationLaunchApp) return null;
    final id = d.notificationResponse?.payload;
    return id == null || id.isEmpty ? null : id;
  }
}

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => NativeReminderScheduler(),
);
