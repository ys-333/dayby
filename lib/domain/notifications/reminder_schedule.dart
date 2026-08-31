import 'package:timezone/timezone.dart' as tz;

import '../time/accounting_calendar.dart';
import '../time/civil_date.dart';
import '../time/clock.dart';
import 'reminder_settings.dart';

/// What a scheduled reminder is about.
enum ReminderKind {
  /// Today's expected commitments.
  daily,

  /// The week that has just closed.
  weeklyReview,
}

/// One reminder, placed on the clock but not yet composed.
///
/// Carries *when* and *what day it is about* — never the text. Composing the
/// words needs the database; this file is pure and testable precisely because
/// it stops here.
class PendingReminder {
  const PendingReminder({
    required this.kind,
    required this.fireAt,
    required this.accountingDate,
    this.reviewWeek,
  });

  final ReminderKind kind;

  /// The instant to hand the platform, in the accounting zone.
  final tz.TZDateTime fireAt;

  /// The accounting day this reminder describes.
  ///
  /// Not the calendar day it fires on. A reminder set for 03:00 fires before
  /// the 04:00 boundary and therefore describes *yesterday* — the day the user
  /// is still finishing. Getting this wrong would have the notification and the
  /// app disagreeing about what day it is.
  final CivilDate accountingDate;

  /// The week being reported, for [ReminderKind.weeklyReview] only.
  final CivilDateRange? reviewWeek;

  /// A stable id, so a specific reminder can later be cancelled by name.
  ///
  /// Derived from the accounting date rather than the position in a batch: the
  /// whole set is rescheduled on every resume and every write, and an
  /// index-based id would point at a different day each time. Cancelling
  /// "today's reminder" when the last commitment is ticked needs the id to mean
  /// the same thing across two separate schedulings.
  int get id => accountingDate.epochDay * 10 + kind.index;

  @override
  bool operator ==(Object other) =>
      other is PendingReminder &&
      other.kind == kind &&
      other.fireAt == fireAt &&
      other.accountingDate == accountingDate;

  @override
  int get hashCode => Object.hash(kind, fireAt, accountingDate);

  @override
  String toString() =>
      'PendingReminder(${kind.name} at $fireAt for $accountingDate)';
}

/// Decides *when* reminders fire. Pure: no database, no platform, no ambient
/// clock.
///
/// Every question this answers is deterministic given a calendar, a settings
/// object and a fixed clock — which is the point. The DST and day-boundary
/// cases below cannot be exercised any other way, and they are exactly the ones
/// that would otherwise be found by a user getting a notification about the
/// wrong day.
class ReminderSchedule {
  const ReminderSchedule(this.calendar);

  final AccountingCalendar calendar;

  /// Default horizon.
  ///
  /// Long enough that someone who does not open the app for a week keeps being
  /// reminded; short enough that pre-rendered text cannot drift far from the
  /// schedule that produced it.
  static const int defaultHorizonDays = 7;

  /// The next reminders to hand the platform, soonest first.
  ///
  /// Returns at most one per day. Where a day carries both a daily reminder and
  /// a week review, **only the review is emitted** — two notifications in the
  /// same minute is one too many, and the review is the one carrying news.
  List<PendingReminder> next(
    ReminderSettings settings,
    Clock clock, {
    int horizonDays = defaultHorizonDays,
  }) {
    if (settings.isSilent) return const [];

    final now = tz.TZDateTime.from(clock.nowUtc(), calendar.zone);
    final out = <PendingReminder>[];

    // Start a day early. A reminder set for 23:00 and evaluated at 00:30 has
    // today's slot already behind it, but yesterday's calendar date is where the
    // *next* one is found when the clock is just past midnight and the boundary
    // has not yet passed.
    var date = CivilDate(now.year, now.month, now.day).plusDays(-1);

    // Bounded by days examined rather than reminders emitted, so a horizon that
    // lands entirely in the past cannot spin.
    for (var i = 0; i <= horizonDays + 1 && out.length < horizonDays; i++) {
      final fireAt = _fireOn(date, settings);
      date = date.plusDays(1);

      if (!fireAt.isAfter(now)) continue;

      final reminder = _reminderAt(fireAt, settings);
      if (reminder != null) out.add(reminder);
    }

    return out;
  }

  /// The instant the reminder occurs on a given *calendar* date.
  ///
  /// `TZDateTime` normalises a wall time that does not exist — the hour skipped
  /// by a spring-forward — rather than throwing. That is the behaviour we want:
  /// the reminder still happens that day, shifted by the gap, instead of being
  /// silently dropped.
  tz.TZDateTime _fireOn(CivilDate date, ReminderSettings settings) =>
      tz.TZDateTime(
        calendar.zone,
        date.year,
        date.month,
        date.day,
        settings.hour,
        settings.minute,
      );

  PendingReminder? _reminderAt(tz.TZDateTime fireAt, ReminderSettings settings) {
    final accountingDate = calendar.accountingDateOf(fireAt);

    // A reminder landing on the first day of an accounting week is the first
    // moment the previous week can be judged: `isPeriodClosed` is
    // `period.end < today`, and that becomes true exactly here.
    final isFirstDayOfWeek = accountingDate == calendar.startOfWeek(accountingDate);

    if (settings.weeklyReviewEnabled && isFirstDayOfWeek) {
      final previousWeekEnd = accountingDate.plusDays(-1);
      return PendingReminder(
        kind: ReminderKind.weeklyReview,
        fireAt: fireAt,
        accountingDate: accountingDate,
        reviewWeek: CivilDateRange(
          calendar.startOfWeek(previousWeekEnd),
          previousWeekEnd,
        ),
      );
    }

    if (settings.dailyEnabled) {
      return PendingReminder(
        kind: ReminderKind.daily,
        fireAt: fireAt,
        accountingDate: accountingDate,
      );
    }

    // Weekly review on, daily off, and this is not a review day: nothing to say.
    return null;
  }
}
