import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/notifications/reminder_schedule.dart';
import 'package:riyaz/domain/notifications/reminder_settings.dart';
import 'package:riyaz/domain/time/accounting_calendar.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/domain/time/clock.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  AccountingCalendar calendarIn(
    String zone, {
    int boundary = 4,
    int weekStartsOn = DateTime.monday,
  }) =>
      AccountingCalendar(
        zone: tz.getLocation(zone),
        dayBoundaryHour: boundary,
        weekStartsOn: weekStartsOn,
      );

  const daily = ReminderSettings(dailyEnabled: true, hour: 8);

  group('nothing to schedule', () {
    test('both reminders off produces nothing at all', () {
      final schedule = ReminderSchedule(calendarIn('Asia/Kolkata'));
      expect(
        schedule.next(
          const ReminderSettings(),
          FixedClock.iso('2026-09-01T10:00:00+05:30'),
        ),
        isEmpty,
      );
    });
  });

  group('the daily reminder', () {
    test('fills the horizon, one per day, soonest first', () {
      final schedule = ReminderSchedule(calendarIn('Asia/Kolkata'));
      final out = schedule.next(
        daily,
        FixedClock.iso('2026-09-01T10:00:00+05:30'),
      );

      expect(out, hasLength(ReminderSchedule.defaultHorizonDays));
      for (var i = 1; i < out.length; i++) {
        expect(out[i].fireAt.isAfter(out[i - 1].fireAt), isTrue);
      }
      expect(
        out.map((r) => r.accountingDate).toSet(),
        hasLength(out.length),
        reason: 'one reminder per accounting day, never two',
      );
    });

    test('honours the horizon it is given', () {
      final schedule = ReminderSchedule(calendarIn('Asia/Kolkata'));
      final out = schedule.next(
        daily,
        FixedClock.iso('2026-09-01T10:00:00+05:30'),
        horizonDays: 3,
      );
      expect(out, hasLength(3));
    });

    test('today is skipped once its time has passed', () {
      final schedule = ReminderSchedule(calendarIn('Asia/Kolkata'));
      // 10:00, reminder at 08:00 — today's slot is gone.
      final out = schedule.next(
        daily,
        FixedClock.iso('2026-09-01T10:00:00+05:30'),
      );
      expect(out.first.fireAt.day, 2);
    });

    test('today is included when its time is still ahead', () {
      final schedule = ReminderSchedule(calendarIn('Asia/Kolkata'));
      final out = schedule.next(
        daily,
        FixedClock.iso('2026-09-01T06:00:00+05:30'),
      );
      expect(out.first.fireAt.day, 1);
      expect(out.first.fireAt.hour, 8);
    });

    test('a reminder due one minute from now is not lost', () {
      final schedule = ReminderSchedule(calendarIn('Asia/Kolkata'));
      final out = schedule.next(
        daily,
        FixedClock.iso('2026-09-01T07:59:00+05:30'),
      );
      expect(out.first.fireAt.day, 1);
      expect(out.first.fireAt.hour, 8);
    });

    test('the fire time is wall-clock, in the accounting zone', () {
      final schedule = ReminderSchedule(calendarIn('Europe/Berlin'));
      final out = schedule.next(
        const ReminderSettings(dailyEnabled: true, hour: 8, minute: 30),
        FixedClock.iso('2026-09-01T00:00:00Z'),
      );
      expect(out.first.fireAt.hour, 8);
      expect(out.first.fireAt.minute, 30);
      expect(out.first.fireAt.location.name, 'Europe/Berlin');
    });
  });

  group('the day boundary decides which day a reminder is about', () {
    test('a morning reminder describes the day it fires on', () {
      final schedule = ReminderSchedule(calendarIn('Asia/Kolkata'));
      final out = schedule.next(
        daily,
        FixedClock.iso('2026-09-01T06:00:00+05:30'),
      );
      expect(out.first.fireAt.day, 1);
      expect(out.first.accountingDate, const CivilDate(2026, 9, 1));
    });

    test('a reminder before 04:00 describes the previous accounting day', () {
      // The whole point of the 4 AM boundary: at 03:00 the user has not slept,
      // so they are still finishing yesterday. A notification listing today's
      // commitments at that hour would disagree with every screen in the app.
      final schedule = ReminderSchedule(calendarIn('Asia/Kolkata'));
      final out = schedule.next(
        const ReminderSettings(dailyEnabled: true, hour: 3),
        FixedClock.iso('2026-09-01T00:30:00+05:30'),
      );

      expect(out.first.fireAt.day, 1);
      expect(
        out.first.accountingDate,
        const CivilDate(2026, 8, 31),
        reason: '03:00 on 1 Sep is still 31 Aug to the accounting engine',
      );
    });

    test('a reminder exactly at the boundary belongs to the new day', () {
      final schedule = ReminderSchedule(calendarIn('Asia/Kolkata'));
      final out = schedule.next(
        const ReminderSettings(dailyEnabled: true, hour: 4),
        FixedClock.iso('2026-09-01T00:30:00+05:30'),
      );
      expect(out.first.accountingDate, const CivilDate(2026, 9, 1));
    });

    test('a non-default boundary moves the cut with it', () {
      final schedule = ReminderSchedule(calendarIn('Asia/Kolkata', boundary: 6));
      final out = schedule.next(
        const ReminderSettings(dailyEnabled: true, hour: 5),
        FixedClock.iso('2026-09-01T00:30:00+05:30'),
      );
      expect(out.first.accountingDate, const CivilDate(2026, 8, 31));
    });

    test('ids are stable across two separate schedulings', () {
      // Cancelling "today's reminder" when the last commitment is ticked needs
      // the id to mean the same thing as it did when it was scheduled.
      final schedule = ReminderSchedule(calendarIn('Asia/Kolkata'));
      final first = schedule.next(
        daily,
        FixedClock.iso('2026-09-01T06:00:00+05:30'),
      );
      final second = schedule.next(
        daily,
        FixedClock.iso('2026-09-01T07:00:00+05:30'),
      );
      expect(first.first.id, second.first.id);
    });

    test('ids are unique within a batch', () {
      final schedule = ReminderSchedule(calendarIn('Asia/Kolkata'));
      final out = schedule.next(
        const ReminderSettings(
          dailyEnabled: true,
          hour: 8,
          weeklyReviewEnabled: true,
        ),
        FixedClock.iso('2026-09-01T06:00:00+05:30'),
      );
      expect(out.map((r) => r.id).toSet(), hasLength(out.length));
    });
  });

  group('daylight saving', () {
    // Europe/Berlin springs forward 02:00 → 03:00 on 29 March 2026, and falls
    // back 03:00 → 02:00 on 25 October 2026.

    test('spring forward: a reminder inside the lost hour still fires once', () {
      final schedule = ReminderSchedule(calendarIn('Europe/Berlin'));
      final out = schedule.next(
        const ReminderSettings(dailyEnabled: true, hour: 2, minute: 30),
        FixedClock.iso('2026-03-27T12:00:00Z'),
        horizonDays: 5,
      );

      // 02:30 does not exist on the 29th. What matters is that the day is not
      // skipped and does not fire twice — not which side of the gap it lands on.
      final onTheGapDay =
          out.where((r) => r.fireAt.month == 3 && r.fireAt.day == 29);
      expect(onTheGapDay, hasLength(1),
          reason: 'a reminder must not vanish because the clock jumped');
    });

    test('fall back: the repeated hour still yields exactly one reminder', () {
      final schedule = ReminderSchedule(calendarIn('Europe/Berlin'));
      final out = schedule.next(
        const ReminderSettings(dailyEnabled: true, hour: 2, minute: 30),
        FixedClock.iso('2026-10-23T12:00:00Z'),
        horizonDays: 5,
      );

      final onTheDoubledDay =
          out.where((r) => r.fireAt.month == 10 && r.fireAt.day == 25);
      expect(onTheDoubledDay, hasLength(1),
          reason: '02:30 happens twice that morning; the user asked to be '
              'reminded once');
    });

    test('a reminder keeps its wall-clock hour across a transition', () {
      // The user picked "08:00" on a clock. It must still read 08:00 after the
      // change, not 07:00 — this is why the hour is stored as wall time rather
      // than as an offset.
      final schedule = ReminderSchedule(calendarIn('Europe/Berlin'));
      final out = schedule.next(
        daily,
        FixedClock.iso('2026-10-23T12:00:00Z'),
        horizonDays: 5,
      );

      expect(out.every((r) => r.fireAt.hour == 8), isTrue);
      expect(
        out.any((r) => r.fireAt.month == 10 && r.fireAt.day == 25),
        isTrue,
        reason: 'the transition day itself must be covered',
      );
    });
  });

  group('the weekly review', () {
    test('fires on the first accounting day of a week', () {
      // 7 Sep 2026 is a Monday.
      final schedule = ReminderSchedule(calendarIn('Asia/Kolkata'));
      final out = schedule.next(
        const ReminderSettings(
          dailyEnabled: true,
          hour: 8,
          weeklyReviewEnabled: true,
        ),
        FixedClock.iso('2026-09-01T10:00:00+05:30'),
      );

      final reviews = out.where((r) => r.kind == ReminderKind.weeklyReview);
      expect(reviews, hasLength(1));
      expect(reviews.first.accountingDate, const CivilDate(2026, 9, 7));
    });

    test('it reports the week that just closed, not the new one', () {
      final schedule = ReminderSchedule(calendarIn('Asia/Kolkata'));
      final out = schedule.next(
        const ReminderSettings(
          dailyEnabled: true,
          hour: 8,
          weeklyReviewEnabled: true,
        ),
        FixedClock.iso('2026-09-01T10:00:00+05:30'),
      );

      final review =
          out.firstWhere((r) => r.kind == ReminderKind.weeklyReview);
      expect(review.reviewWeek!.start, const CivilDate(2026, 8, 31));
      expect(review.reviewWeek!.end, const CivilDate(2026, 9, 6));
      expect(review.reviewWeek!.lengthInDays, 7);
    });

    test('weekStartsOn moves the review day with it', () {
      // 6 Sep 2026 is a Sunday.
      final schedule = ReminderSchedule(
        calendarIn('Asia/Kolkata', weekStartsOn: DateTime.sunday),
      );
      final out = schedule.next(
        const ReminderSettings(
          dailyEnabled: true,
          hour: 8,
          weeklyReviewEnabled: true,
        ),
        FixedClock.iso('2026-09-01T10:00:00+05:30'),
      );

      final review =
          out.firstWhere((r) => r.kind == ReminderKind.weeklyReview);
      expect(review.accountingDate, const CivilDate(2026, 9, 6));
      expect(review.reviewWeek!.end, const CivilDate(2026, 9, 5));
    });

    test('a review day carries the review only, never both', () {
      final schedule = ReminderSchedule(calendarIn('Asia/Kolkata'));
      final out = schedule.next(
        const ReminderSettings(
          dailyEnabled: true,
          hour: 8,
          weeklyReviewEnabled: true,
        ),
        FixedClock.iso('2026-09-01T10:00:00+05:30'),
      );

      final onTheSeventh =
          out.where((r) => r.accountingDate == const CivilDate(2026, 9, 7));
      expect(onTheSeventh, hasLength(1));
      expect(onTheSeventh.first.kind, ReminderKind.weeklyReview);
    });

    test('with the daily reminder off, only review days are scheduled', () {
      final schedule = ReminderSchedule(calendarIn('Asia/Kolkata'));
      final out = schedule.next(
        const ReminderSettings(hour: 8, weeklyReviewEnabled: true),
        FixedClock.iso('2026-09-01T10:00:00+05:30'),
      );

      expect(out, hasLength(1));
      expect(out.single.kind, ReminderKind.weeklyReview);
      expect(out.single.accountingDate, const CivilDate(2026, 9, 7));
    });

    test('a review at 03:00 reports the week ending the day before that', () {
      // Both rules at once: the pre-boundary shift decides the accounting date,
      // and the accounting date decides which week is being reported.
      final schedule = ReminderSchedule(calendarIn('Asia/Kolkata'));
      final out = schedule.next(
        const ReminderSettings(hour: 3, weeklyReviewEnabled: true),
        FixedClock.iso('2026-09-01T10:00:00+05:30'),
      );

      final review = out.single;
      // Fires early on Tue 8 Sep by the calendar, which is still Mon 7 Sep.
      expect(review.fireAt.day, 8);
      expect(review.accountingDate, const CivilDate(2026, 9, 7));
      expect(review.reviewWeek!.end, const CivilDate(2026, 9, 6));
    });
  });
}
