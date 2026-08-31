import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// **THROWAWAY.** Delete this file before Phase 3 starts.
///
/// It exists to answer one question that no test on this machine can:
/// *does a scheduled notification actually get delivered on this phone?*
///
/// The device is an iQOO running Vivo's Funtouch/OriginOS, which is among the
/// most aggressive background-app killers shipping. If reminders are silently
/// dropped there, the pre-render architecture in
/// `docs/specs/2026-09-01-notifications.md` is sound and the feature is still
/// dead on this hardware — and that is worth knowing before six phases are
/// built on top of it.
///
/// Nothing here is the real design. The real one composes its text in
/// `lib/domain/`, goes through an interface with an in-memory double, and never
/// hardcodes a string. This just proves the pipe is open.
class NotificationSpike {
  NotificationSpike(this.zone);

  /// The app's accounting zone, not a fresh lookup — the same [tz.Location] the
  /// accounting engine uses, so a spike that fires at the wrong hour is telling
  /// us something real rather than reporting its own separate bug.
  final tz.Location zone;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String channelId = 'riyaz.reminders';

  /// Two notifications, deliberately.
  ///
  /// The near one proves delivery works at all with the screen locked. The far
  /// one is the reboot test: restart the phone after the first arrives and see
  /// whether the second still lands, which is the only way to know the boot
  /// receiver is wired up.
  static const Duration nearDelay = Duration(minutes: 2);
  static const Duration farDelay = Duration(minutes: 15);

  Future<SpikeResult> run() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        // The launcher icon is a placeholder. Android silhouettes the small
        // icon, so a coloured asset renders as a white blob — a real
        // monochrome drawable is Phase 3 work.
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      return const SpikeResult(ok: false, message: 'No Android implementation.');
    }

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        'Reminders',
        description: 'Daily reminders and the weekly review.',
      ),
    );

    // Android 13+ refuses to post anything until this is granted. Asking here
    // is spike-only: the real flow asks on first enable in Settings, never at
    // startup, because a prompt before the user has shown interest is how an
    // app gets permanently denied.
    final granted = await android.requestNotificationsPermission() ?? false;
    if (!granted) {
      return const SpikeResult(
        ok: false,
        message: 'Notification permission denied. Nothing was scheduled.',
      );
    }

    await _plugin.cancelAll();

    final now = tz.TZDateTime.now(zone);
    final near = now.add(nearDelay);
    final far = now.add(farDelay);

    await _schedule(1, near, 'Riyaz spike · 1 of 2',
        'Delivery works. Now reboot the phone.');
    await _schedule(2, far, 'Riyaz spike · 2 of 2',
        'Survived the reboot. The boot receiver is wired up.');

    final pending = await _plugin.pendingNotificationRequests();
    debugPrint('Spike scheduled ${pending.length} at $near / $far');

    return SpikeResult(
      ok: true,
      message: 'Scheduled for ${_hhmm(near)} and ${_hhmm(far)}. '
          'Lock the phone and leave it alone.',
    );
  }

  Future<void> _schedule(
    int id,
    tz.TZDateTime at,
    String title,
    String body,
  ) =>
      _plugin.zonedSchedule(
        id: id,
        scheduledDate: at,
        title: title,
        body: body,
        // Inexact on purpose. Exact alarms need SCHEDULE_EXACT_ALARM, which
        // Android 14 restricts to alarm-clock and calendar apps — Riyaz would
        // not qualify. The cost is that delivery can drift by a few minutes
        // under Doze, which a habit reminder can afford.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            'Reminders',
            channelDescription: 'Daily reminders and the weekly review.',
          ),
        ),
      );

  static String _hhmm(tz.TZDateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}

/// What the spike wants to tell the user, on a screen rather than in a log.
class SpikeResult {
  const SpikeResult({required this.ok, required this.message});

  final bool ok;
  final String message;
}
