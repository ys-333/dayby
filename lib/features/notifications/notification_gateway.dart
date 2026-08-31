import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:timezone/timezone.dart' as tz;

import 'reminder_copy.dart';

part 'notification_gateway.g.dart';

/// One notification, already composed, waiting on the clock.
///
/// Everything here was decided in Dart — `ReminderSchedule` chose the instant
/// and `ReminderCopy` chose the words. The platform layer below does no
/// arithmetic and knows nothing about skips, pauses or period targets, for the
/// same reason the home-screen widget does not: a second implementation of the
/// scoring rules would eventually disagree with the first.
class ScheduledNotification {
  const ScheduledNotification({
    required this.id,
    required this.fireAt,
    required this.text,
    required this.route,
  });

  final int id;
  final tz.TZDateTime fireAt;
  final ReminderText text;

  /// Where tapping it should land. Carried as the platform payload.
  final String route;

  @override
  String toString() => 'ScheduledNotification($id at $fireAt → $route)';
}

/// The platform port for reminders.
///
/// An interface, not a concrete class, and for the same reason
/// [BackupFileStore] is one: widget tests run inside a fake-async zone where
/// real platform I/O never completes, so a screen that schedules during a
/// `pumpAndSettle` hangs forever rather than failing. Tests substitute an
/// in-memory implementation; the real one is exercised on a device.
abstract interface class NotificationGateway {
  /// Asks the OS for permission if it does not already have it.
  ///
  /// Returns whether notifications may actually be posted. Called on first
  /// enable in Settings, never at startup: a prompt before the user has shown
  /// any interest is how an app gets permanently denied, and that is far harder
  /// to win back than an in-app toggle.
  Future<bool> ensurePermission();

  /// Replaces the entire pending set.
  ///
  /// Replace rather than add, deliberately, and it is the only scheduling verb
  /// on this interface. The whole set is recomputed on every resume and every
  /// tracking write; an `add` would let yesterday's notifications accumulate
  /// behind today's, and nothing would ever notice.
  Future<void> replaceAll(List<ScheduledNotification> items);

  /// Cancels one notification by its stable id.
  ///
  /// Used when the last pending commitment is ticked: being reminded to do what
  /// you have already done is the worst failure this feature has.
  Future<void> cancel(int id);

  Future<void> cancelAll();

  /// Ids the platform still holds. Diagnostic — tests assert against it.
  Future<List<int>> pendingIds();
}

/// The real gateway, over `flutter_local_notifications`.
///
/// Every failure is swallowed and logged rather than rethrown, exactly as
/// `WidgetBridge` does. A revoked permission, an OEM that drops alarms, or a
/// platform with no notifications at all must never break the app running in
/// front of the user — reminders are a convenience, and the tracking they
/// support is not.
class LocalNotificationGateway implements NotificationGateway {
  LocalNotificationGateway({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// One channel. No sound escalation, no second "urgent" channel — the whole
  /// product stance is that a reminder informs rather than demands.
  static const String channelId = 'riyaz.reminders';
  static const String channelName = 'Reminders';
  static const String channelDescription =
      'Daily reminders and the weekly review.';

  /// A monochrome drawable. Android silhouettes the small icon, so a coloured
  /// asset renders as a white blob — the launcher icon the spike used did
  /// exactly that.
  static const String smallIcon = '@drawable/ic_notification';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialised = false;

  /// Prepares the plugin and the channel. Safe to call more than once.
  Future<void> initialize({void Function(String route)? onTap}) async {
    if (_initialised) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(smallIcon),
        ),
        onDidReceiveNotificationResponse: (response) {
          final route = response.payload;
          if (route != null && route.isNotEmpty) onTap?.call(route);
        },
      );
      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
        ),
      );
      _initialised = true;
    } on Object catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> ensurePermission() async {
    await initialize();
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } on Object catch (e) {
      debugPrint('Notification permission request failed: $e');
      return false;
    }
  }

  @override
  Future<void> replaceAll(List<ScheduledNotification> items) async {
    await initialize();
    try {
      await _plugin.cancelAll();
      for (final item in items) {
        await _plugin.zonedSchedule(
          id: item.id,
          scheduledDate: item.fireAt,
          title: item.text.title,
          body: item.text.body,
          payload: item.route,
          // Inexact on purpose. Exact alarms need SCHEDULE_EXACT_ALARM, which
          // Android 14 restricts to alarm-clock and calendar apps — a habit
          // tracker would not qualify, and does not need minute precision. The
          // measured cost on the device spike was a few minutes of drift.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              channelName,
              channelDescription: channelDescription,
              styleInformation: BigTextStyleInformation(
                item.text.lines.join('\n'),
                contentTitle: item.text.title,
              ),
            ),
          ),
        );
      }
    } on Object catch (e) {
      debugPrint('Scheduling reminders failed: $e');
    }
  }

  @override
  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } on Object catch (e) {
      debugPrint('Cancelling reminder $id failed: $e');
    }
  }

  @override
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } on Object catch (e) {
      debugPrint('Cancelling reminders failed: $e');
    }
  }

  @override
  Future<List<int>> pendingIds() async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return [for (final p in pending) p.id];
    } on Object catch (e) {
      debugPrint('Reading pending reminders failed: $e');
      return const [];
    }
  }
}

@Riverpod(keepAlive: true)
NotificationGateway notificationGateway(Ref ref) => LocalNotificationGateway();
