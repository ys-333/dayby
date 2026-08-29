import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/accounting/accounting_engine.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/accounting/resolved_occurrence.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/pause_period.dart';
import 'package:riyaz/domain/model/schedule.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/recurrence/expected_occurrence.dart';
import 'package:riyaz/domain/recurrence/recurrence_engine.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/domain/time/clock.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/dates.dart';
import '../../support/fixtures.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late AccountingEngine engine;

  // "Now" is Friday 2026-08-28, 10:00 IST. Today's accounting day is Aug 28.
  final now = FixedClock.iso('2026-08-28T10:00:00+05:30');

  setUp(() {
    final calendar = calendarFor('Asia/Kolkata');
    engine = AccountingEngine(
      calendar: calendar,
      recurrence: RecurrenceEngine(calendar),
    );
  });

  List<ResolvedOccurrence> resolveDaily({
    required CivilDate from,
    required CivilDate to,
    List<TrackingEvent> events = const [],
    List<PausePeriod> pauses = const [],
    int target = 1,
    Clock? clock,
  }) =>
      engine.resolveRange(
        commitmentId: commitmentId,
        schedules: [
          schedule(
            frequency: Frequency.daily(target: target),
            from: d(2026, 8, 1),
          ),
        ],
        pauses: pauses,
        events: events,
        range: CivilDateRange(from, to),
        clock: clock ?? now,
      );

  List<ResolvedOccurrence> resolveWeekly({
    required CivilDate from,
    required CivilDate to,
    List<TrackingEvent> events = const [],
    int target = 4,
  }) =>
      engine.resolveRange(
        commitmentId: commitmentId,
        schedules: [
          schedule(
            frequency: Frequency.timesPerWeek(target: target),
            from: d(2026, 8, 1),
          ),
        ],
        pauses: const [],
        events: events,
        range: CivilDateRange(from, to),
        clock: now,
      );

  group('daily occurrences', () {
    test('a future day is pending and out of the denominator', () {
      final r = resolveDaily(from: d(2026, 8, 30), to: d(2026, 8, 30)).single;
      expect(r.status, OccurrenceStatus.pending);
      expect(r.isEligible, isFalse);
      expect(r.credit, 0);
    });

    test('today with nothing recorded is pending, not missed', () {
      final r = resolveDaily(from: d(2026, 8, 28), to: d(2026, 8, 28)).single;
      expect(r.status, OccurrenceStatus.pending);
      expect(r.isEligible, isFalse);
    });

    test('yesterday with nothing recorded is missed', () {
      final r = resolveDaily(from: d(2026, 8, 27), to: d(2026, 8, 27)).single;
      expect(r.status, OccurrenceStatus.missed);
      expect(r.isEligible, isTrue);
      expect(r.credit, 0);
    });

    test('pending becomes missed only once the day closes', () {
      final duringAug27 = FixedClock.iso('2026-08-27T22:00:00+05:30');
      expect(
        resolveDaily(
          from: d(2026, 8, 27),
          to: d(2026, 8, 27),
          clock: duringAug27,
        ).single.status,
        OccurrenceStatus.pending,
      );
      // 01:30 the next morning is still the Aug 27 accounting day.
      final after = FixedClock.iso('2026-08-28T01:30:00+05:30');
      expect(
        resolveDaily(from: d(2026, 8, 27), to: d(2026, 8, 27), clock: after)
            .single
            .status,
        OccurrenceStatus.pending,
      );
      // 04:00 closes it.
      final closed = FixedClock.iso('2026-08-28T04:00:00+05:30');
      expect(
        resolveDaily(from: d(2026, 8, 27), to: d(2026, 8, 27), clock: closed)
            .single
            .status,
        OccurrenceStatus.missed,
      );
    });

    test('a completion resolves to done with full credit', () {
      final r = resolveDaily(
        from: d(2026, 8, 27),
        to: d(2026, 8, 27),
        events: [event(d(2026, 8, 27))],
      ).single;
      expect(r.status, OccurrenceStatus.done);
      expect(r.credit, 1.0);
    });

    test('today can be done immediately without waiting for close', () {
      final r = resolveDaily(
        from: d(2026, 8, 28),
        to: d(2026, 8, 28),
        events: [event(d(2026, 8, 28))],
      ).single;
      expect(r.status, OccurrenceStatus.done);
    });

    test('a closed shortfall is partial at half credit', () {
      final r = resolveDaily(
        from: d(2026, 8, 27),
        to: d(2026, 8, 27),
        events: [event(d(2026, 8, 27), kind: TrackingKind.partial)],
      ).single;
      expect(r.status, OccurrenceStatus.partial);
      expect(r.credit, 0.5);
    });

    test('a skip leaves the denominator instead of scoring zero', () {
      final r = resolveDaily(
        from: d(2026, 8, 27),
        to: d(2026, 8, 27),
        events: [event(d(2026, 8, 27), kind: TrackingKind.skipped)],
      ).single;
      expect(r.status, OccurrenceStatus.skipped);
      expect(r.isEligible, isFalse);
      expect(r.credit, 0);
    });

    test('a skip outranks a completion recorded the same day', () {
      final r = resolveDaily(
        from: d(2026, 8, 27),
        to: d(2026, 8, 27),
        events: [
          event(d(2026, 8, 27)),
          event(d(2026, 8, 27), kind: TrackingKind.skipped),
        ],
      ).single;
      expect(r.status, OccurrenceStatus.skipped);
    });

    test('a multi-count target accumulates across events', () {
      final open = resolveDaily(
        from: d(2026, 8, 28),
        to: d(2026, 8, 28),
        target: 2,
        events: [event(d(2026, 8, 28))],
      ).single;
      expect(open.status, OccurrenceStatus.pending);
      expect(open.completed, 1);
      expect(open.progressLabel, '1 / 2');

      final met = resolveDaily(
        from: d(2026, 8, 28),
        to: d(2026, 8, 28),
        target: 2,
        events: [event(d(2026, 8, 28)), event(d(2026, 8, 28), id: 'e2')],
      ).single;
      expect(met.status, OccurrenceStatus.done);
    });

    test('a closed multi-count shortfall is partial', () {
      final r = resolveDaily(
        from: d(2026, 8, 27),
        to: d(2026, 8, 27),
        target: 2,
        events: [event(d(2026, 8, 27))],
      ).single;
      expect(r.status, OccurrenceStatus.partial);
      expect(r.completed, 1);
    });

    test('events from other commitments are ignored', () {
      final foreign = event(d(2026, 8, 27)).copyWith(commitmentId: 'other');
      final r = resolveDaily(
        from: d(2026, 8, 27),
        to: d(2026, 8, 27),
        events: [foreign],
      ).single;
      expect(r.status, OccurrenceStatus.missed);
    });
  });

  group('period occurrences', () {
    test('an open week behind target is pending, never missed', () {
      // Today is Friday Aug 28; the week Aug 24-30 is still open.
      final r = resolveWeekly(
        from: d(2026, 8, 24),
        to: d(2026, 8, 30),
        events: [event(d(2026, 8, 24)), event(d(2026, 8, 25), id: 'e2')],
      ).single;
      expect(r.status, OccurrenceStatus.pending);
      expect(r.completed, 2);
      expect(r.target, 4);
      expect(r.progressLabel, '2 / 4');
      expect(r.isEligible, isFalse);
    });

    test('there is never a missed Wednesday inside a weekly target', () {
      final all = resolveWeekly(
        from: d(2026, 8, 24),
        to: d(2026, 8, 30),
        events: [event(d(2026, 8, 24))],
      );
      expect(all, hasLength(1));
      expect(all.single.occurrence, isA<PeriodOccurrence>());
      expect(all.any((r) => r.status == OccurrenceStatus.missed), isFalse);
    });

    test('hitting the target closes the week early', () {
      final r = resolveWeekly(
        from: d(2026, 8, 24),
        to: d(2026, 8, 30),
        events: [
          for (var i = 0; i < 4; i++)
            event(d(2026, 8, 24 + i), id: 'e$i'),
        ],
      ).single;
      expect(r.status, OccurrenceStatus.done);
      expect(r.credit, 1.0);
    });

    test('the denominator is the target, not the number of days', () {
      final r = resolveWeekly(from: d(2026, 8, 24), to: d(2026, 8, 30)).single;
      expect(r.target, 4);
      expect(r.occurrence.span.lengthInDays, 7);
    });

    test('a closed week short of target scores its completion ratio', () {
      // Week of Aug 17-23 is fully in the past.
      final r = resolveWeekly(
        from: d(2026, 8, 17),
        to: d(2026, 8, 23),
        events: [
          for (var i = 0; i < 3; i++)
            event(d(2026, 8, 17 + i), id: 'e$i'),
        ],
      ).single;
      expect(r.status, OccurrenceStatus.partial);
      expect(r.completed, 3);
      expect(r.credit, closeTo(0.75, 1e-9));
    });

    test('a closed empty week is missed', () {
      final r = resolveWeekly(from: d(2026, 8, 17), to: d(2026, 8, 23)).single;
      expect(r.status, OccurrenceStatus.missed);
      expect(r.credit, 0);
    });

    test('overshooting a target cannot exceed full credit', () {
      final r = resolveWeekly(
        from: d(2026, 8, 17),
        to: d(2026, 8, 23),
        events: [
          for (var i = 0; i < 6; i++)
            event(d(2026, 8, 17 + i), id: 'e$i'),
        ],
      ).single;
      expect(r.status, OccurrenceStatus.done);
      expect(r.credit, 1.0);
    });

    test('a monthly target stays open all month', () {
      final r = engine.resolveRange(
        commitmentId: commitmentId,
        schedules: [
          schedule(
            frequency: const Frequency.timesPerMonth(target: 2),
            from: d(2026, 8, 1),
          ),
        ],
        pauses: const [],
        events: [event(d(2026, 8, 10))],
        range: CivilDateRange(d(2026, 8, 1), d(2026, 8, 31)),
        clock: now,
      ).single;
      expect(r.status, OccurrenceStatus.pending);
      expect(r.progressLabel, '1 / 2');
    });

    // A skipped day used to mark the whole week skipped and reset `completed`
    // to zero, so two real completions rendered as "0 / 3" and the week left
    // the denominator entirely. Found on a device, not by these tests — every
    // other skip case here is daily.
    test('a skipped day does not skip the whole week', () {
      final r = resolveWeekly(
        from: d(2026, 8, 24),
        to: d(2026, 8, 30),
        target: 3,
        events: [
          event(d(2026, 8, 25)),
          event(d(2026, 8, 26), kind: TrackingKind.skipped),
          event(d(2026, 8, 28)),
        ],
      ).single;

      expect(r.status, OccurrenceStatus.pending);
      expect(r.completed, 2, reason: 'completions must survive a skipped day');
      expect(r.progressLabel, '2 / 3');
    });

    test('a skipped day still leaves the week able to close short', () {
      final r = resolveWeekly(
        from: d(2026, 8, 17),
        to: d(2026, 8, 23),
        target: 3,
        events: [
          event(d(2026, 8, 18)),
          event(d(2026, 8, 19), kind: TrackingKind.skipped),
        ],
      ).single;

      expect(r.status, OccurrenceStatus.partial);
      expect(r.completed, 1);
      expect(r.isEligible, isTrue, reason: 'the week stays in the denominator');
    });

    test('a skipped day cannot stop a met target from being done', () {
      final r = resolveWeekly(
        from: d(2026, 8, 24),
        to: d(2026, 8, 30),
        target: 2,
        events: [
          event(d(2026, 8, 25)),
          event(d(2026, 8, 26), kind: TrackingKind.skipped),
          event(d(2026, 8, 27)),
        ],
      ).single;

      expect(r.status, OccurrenceStatus.done);
      expect(r.completed, 2);
    });
  });

  group('statusOnDate', () {
    List<CommitmentSchedule> weekdaysOnly() => [
          schedule(
            frequency: const Frequency.weekdays(
              days: {DateTime.monday, DateTime.wednesday},
            ),
            from: d(2026, 8, 1),
          ),
        ];

    test('a paused date reports paused, not missed', () {
      expect(
        engine.statusOnDate(
          commitmentId: commitmentId,
          schedules: [
            schedule(frequency: const Frequency.daily(), from: d(2026, 8, 1)),
          ],
          pauses: [pause(d(2026, 8, 20), d(2026, 8, 25))],
          events: const [],
          date: d(2026, 8, 22),
          clock: now,
        ),
        OccurrenceStatus.paused,
      );
    });

    test('an unscheduled weekday reports notScheduled', () {
      expect(
        engine.statusOnDate(
          commitmentId: commitmentId,
          schedules: weekdaysOnly(),
          pauses: const [],
          events: const [],
          date: d(2026, 8, 25), // a Tuesday
          clock: now,
        ),
        OccurrenceStatus.notScheduled,
      );
    });

    test('a scheduled weekday still resolves normally', () {
      expect(
        engine.statusOnDate(
          commitmentId: commitmentId,
          schedules: weekdaysOnly(),
          pauses: const [],
          events: const [],
          date: d(2026, 8, 24), // a Monday, in the past
          clock: now,
        ),
        OccurrenceStatus.missed,
      );
    });
  });

  group("the spec's acceptance scenario", () {
    test('five done, three missed, then a return', () {
      final clock = FixedClock.iso('2026-08-10T10:00:00+05:30');
      final done = [1, 2, 3, 4, 5, 9];
      final results = engine.resolveRange(
        commitmentId: commitmentId,
        schedules: [
          schedule(frequency: const Frequency.daily(), from: d(2026, 8, 1)),
        ],
        pauses: const [],
        events: [for (final day in done) event(d(2026, 8, day), id: 'e$day')],
        range: CivilDateRange(d(2026, 8, 1), d(2026, 8, 9)),
        clock: clock,
      );

      expect(
        results.map((r) => r.status).toList(),
        [
          OccurrenceStatus.done,
          OccurrenceStatus.done,
          OccurrenceStatus.done,
          OccurrenceStatus.done,
          OccurrenceStatus.done,
          OccurrenceStatus.missed,
          OccurrenceStatus.missed,
          OccurrenceStatus.missed,
          OccurrenceStatus.done,
        ],
      );
    });

    test('gym on Mon/Tue/Thu/Sat is a perfect week with no missed day', () {
      final clock = FixedClock.iso('2026-09-01T10:00:00+05:30');
      final results = engine.resolveRange(
        commitmentId: commitmentId,
        schedules: [
          schedule(
            frequency: const Frequency.timesPerWeek(target: 4),
            from: d(2026, 8, 1),
          ),
        ],
        pauses: const [],
        events: [
          event(d(2026, 8, 24), id: 'mon'),
          event(d(2026, 8, 25), id: 'tue'),
          event(d(2026, 8, 27), id: 'thu'),
          event(d(2026, 8, 29), id: 'sat'),
        ],
        range: CivilDateRange(d(2026, 8, 24), d(2026, 8, 30)),
        clock: clock,
      );

      expect(results, hasLength(1));
      expect(results.single.status, OccurrenceStatus.done);
      expect(results.single.credit, 1.0);
      // Wednesday Aug 26 never existed as an expectation.
      expect(results.any((r) => r.status == OccurrenceStatus.missed), isFalse);
    });
  });
}
