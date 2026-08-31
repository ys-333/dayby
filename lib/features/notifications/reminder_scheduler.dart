import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/domain/notifications/reminder_schedule.dart';
import 'package:riyaz/domain/notifications/reminder_settings.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/features/home/today_controller.dart';
import 'package:riyaz/features/home/today_view.dart';
import 'package:riyaz/features/review/week_review_controller.dart';

import 'notification_gateway.dart';
import 'reminder_copy.dart';
import 'reminder_settings_controller.dart';

part 'reminder_scheduler.g.dart';

/// Where a tapped reminder lands.
abstract final class ReminderRoutes {
  static const String today = '/';
  static const String review = '/review';
}

/// Composes the three pure pieces and hands the result to the platform.
///
/// [ReminderSchedule] decides *when*, [ReminderCopy] decides *what*, and
/// [NotificationGateway] does the posting. Nothing here re-derives either — this
/// class only reads the database and joins them up.
///
/// **This is where correctness comes from.** The architecture pre-renders
/// notifications days ahead, so the text can go stale; the answer is not
/// cleverness at compose time but rescheduling often, from the two moments that
/// have the app alive and the engines available: a foreground resume, and every
/// tracking write.
class ReminderScheduler {
  ReminderScheduler(this._ref);

  final Ref _ref;

  /// Recomputes the whole pending set and replaces it.
  ///
  /// One operation covers every case, including cancellation. A day whose
  /// commitments are all finished produces no copy, so it simply does not
  /// appear in the replacement set — which is how "the last item was ticked,
  /// drop today's reminder" falls out of rescheduling rather than needing its
  /// own path that could drift from this one.
  Future<void> reschedule() async {
    final gateway = _ref.read(notificationGatewayProvider);
    final settings = _ref.read(reminderSettingsControllerProvider);

    if (settings.isSilent) {
      await gateway.cancelAll();
      return;
    }

    try {
      await gateway.replaceAll(await _compose(settings));
    } on Object catch (e) {
      // Never let a reminder failure break the write that triggered it. The
      // tracking event is the canonical record; the notification is a
      // convenience over the top of it.
      debugPrint('Rescheduling reminders failed: $e');
    }
  }

  Future<List<ScheduledNotification>> _compose(
    ReminderSettings settings,
  ) async {
    final calendar = _ref.read(accountingCalendarProvider);
    final clock = _ref.read(clockProvider);
    final pending = ReminderSchedule(calendar).next(settings, clock);

    final out = <ScheduledNotification>[];
    for (final reminder in pending) {
      final (text, route) = switch (reminder.kind) {
        ReminderKind.daily => (
            ReminderCopy.daily(await _dayView(reminder.accountingDate)),
            ReminderRoutes.today,
          ),
        ReminderKind.weeklyReview => (
            await _reviewText(reminder.reviewWeek!),
            ReminderRoutes.review,
          ),
      };

      // Null means there is nothing worth saying. Post nothing rather than
      // teaching the user that these are safe to swipe away unread.
      if (text == null) continue;

      out.add(ScheduledNotification(
        id: reminder.id,
        fireAt: reminder.fireAt,
        text: text,
        route: route,
      ));
    }
    return out;
  }

  /// One day, built through the same function the Today screen uses.
  ///
  /// Not a parallel implementation: a notification listing different
  /// commitments from the screen it opens would be worse than no notification.
  Future<TodayView> _dayView(CivilDate date) async {
    final calendar = _ref.read(accountingCalendarProvider);
    final snapshot = await _ref
        .read(trackingRepositoryProvider)
        .read(todayViewRange(calendar, date));

    return todayViewFrom(
      snapshot: snapshot,
      date: date,
      recurrence: _ref.read(recurrenceEngineProvider),
      accounting: _ref.read(accountingEngineProvider),
      clock: _ref.read(clockProvider),
    );
  }

  /// The review copy, numbered when it can be and inviting when it cannot.
  ///
  /// The reviewed week has usually not closed at the moment this is scheduled —
  /// the notification is handed to the platform days before it fires — so its
  /// percentage does not exist yet and composing one would be a guess. The
  /// numbered form is used only when the app happens to be opened after the week
  /// closed and before the reminder fires, which a reschedule on resume turns
  /// into the better copy.
  Future<ReminderText?> _reviewText(CivilDateRange week) async {
    final calendar = _ref.read(accountingCalendarProvider);
    final clock = _ref.read(clockProvider);

    if (!calendar.isPeriodClosed(week, clock)) {
      return ReminderCopy.weeklyReviewPending;
    }

    try {
      final review = await _ref.read(weekReviewProvider(week.start).future);
      return ReminderCopy.weeklyReview(review) ??
          ReminderCopy.weeklyReviewPending;
    } on Object catch (e) {
      debugPrint('Composing the week review failed: $e');
      return ReminderCopy.weeklyReviewPending;
    }
  }
}

@Riverpod(keepAlive: true)
ReminderScheduler reminderScheduler(Ref ref) => ReminderScheduler(ref);
