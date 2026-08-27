import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/pause_period.dart';
import 'package:riyaz/domain/model/schedule.dart';
import 'package:riyaz/domain/recurrence/expected_occurrence.dart';
import 'package:riyaz/domain/recurrence/recurrence_engine.dart';
import 'package:riyaz/domain/time/accounting_calendar.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/dates.dart';
import '../../support/fixtures.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late RecurrenceEngine engine;
  setUp(() => engine = RecurrenceEngine(calendarFor('Asia/Kolkata')));

  List<ExpectedOccurrence> run({
    required List<CommitmentSchedule> schedules,
    List<PausePeriod> pauses = const [],
    required CivilDate from,
    required CivilDate to,
  }) =>
      engine.occurrencesIn(
        commitmentId: commitmentId,
        schedules: schedules,
        pauses: pauses,
        range: CivilDateRange(from, to),
      );

  group('daily-shaped frequencies', () {
    test('daily emits one occurrence per day', () {
      final out = run(
        schedules: [
          schedule(frequency: const Frequency.daily(), from: d(2026, 8, 1)),
        ],
        from: d(2026, 8, 24),
        to: d(2026, 8, 30),
      );
      expect(out, hasLength(7));
      expect(out.every((o) => o is DailyOccurrence), isTrue);
    });

    test('daily honours a target above one', () {
      final out = run(
        schedules: [
          schedule(
            frequency: const Frequency.daily(target: 2),
            from: d(2026, 8, 1),
          ),
        ],
        from: d(2026, 8, 24),
        to: d(2026, 8, 24),
      );
      expect(out.single.target, 2);
    });

    test('weekdays emits only the listed days', () {
      final out = run(
        schedules: [
          schedule(
            frequency: const Frequency.weekdays(
              days: {DateTime.monday, DateTime.wednesday, DateTime.friday},
            ),
            from: d(2026, 8, 1),
          ),
        ],
        from: d(2026, 8, 24),
        to: d(2026, 8, 30),
      );
      expect(
        out.cast<DailyOccurrence>().map((o) => o.date).toList(),
        [d(2026, 8, 24), d(2026, 8, 26), d(2026, 8, 28)],
      );
    });

    test('everyNDays counts from the schedule start, not the range start', () {
      final out = run(
        schedules: [
          schedule(
            frequency: const Frequency.everyNDays(n: 3),
            from: d(2026, 8, 1),
          ),
        ],
        from: d(2026, 8, 5),
        to: d(2026, 8, 14),
      );
      expect(
        out.cast<DailyOccurrence>().map((o) => o.date).toList(),
        [d(2026, 8, 7), d(2026, 8, 10), d(2026, 8, 13)],
      );
    });

    test('nothing is expected before the schedule starts', () {
      final out = run(
        schedules: [
          schedule(frequency: const Frequency.daily(), from: d(2026, 8, 10)),
        ],
        from: d(2026, 8, 5),
        to: d(2026, 8, 12),
      );
      expect(out, hasLength(3));
    });

    test('no schedule at all expects nothing', () {
      final out = run(schedules: [], from: d(2026, 8, 1), to: d(2026, 8, 31));
      expect(out, isEmpty);
    });
  });

  group('period-shaped frequencies', () {
    test('4x per week emits ONE period occurrence, never seven days', () {
      final out = run(
        schedules: [
          schedule(
            frequency: const Frequency.timesPerWeek(target: 4),
            from: d(2026, 8, 1),
          ),
        ],
        from: d(2026, 8, 24),
        to: d(2026, 8, 30),
      );
      expect(out, hasLength(1));
      final only = out.single as PeriodOccurrence;
      expect(only.target, 4);
      expect(only.scope, PeriodScope.weekly);
      expect(only.period, CivilDateRange(d(2026, 8, 24), d(2026, 8, 30)));
      expect(out.whereType<DailyOccurrence>(), isEmpty);
    });

    test('a partial week still yields the whole week, once', () {
      final out = run(
        schedules: [
          schedule(
            frequency: const Frequency.timesPerWeek(target: 4),
            from: d(2026, 8, 1),
          ),
        ],
        from: d(2026, 8, 26),
        to: d(2026, 8, 27),
      );
      expect(out, hasLength(1));
      expect(
        (out.single as PeriodOccurrence).period,
        CivilDateRange(d(2026, 8, 24), d(2026, 8, 30)),
      );
    });

    test('monthly target emits one occurrence per month', () {
      final out = run(
        schedules: [
          schedule(
            frequency: const Frequency.timesPerMonth(target: 2),
            from: d(2026, 8, 1),
          ),
        ],
        from: d(2026, 8, 15),
        to: d(2026, 10, 3),
      );
      expect(out, hasLength(3));
      expect(
        out.cast<PeriodOccurrence>().map((o) => o.period.start).toList(),
        [d(2026, 8, 1), d(2026, 9, 1), d(2026, 10, 1)],
      );
    });
  });

  group('schedule versioning', () {
    List<CommitmentSchedule> versioned() => [
          schedule(
            id: 'v1',
            frequency: const Frequency.daily(),
            from: d(2026, 8, 1),
            to: d(2026, 9, 30),
          ),
          schedule(
            id: 'v2',
            frequency: const Frequency.timesPerWeek(target: 3),
            from: d(2026, 10, 1),
          ),
        ];

    test('August is judged by the old version', () {
      final out =
          run(schedules: versioned(), from: d(2026, 8, 1), to: d(2026, 8, 31));
      expect(out, hasLength(31));
      expect(out.every((o) => o is DailyOccurrence), isTrue);
    });

    test('October is judged by the new version', () {
      final out = run(
        schedules: versioned(),
        from: d(2026, 10, 1),
        to: d(2026, 10, 31),
      );
      expect(out.every((o) => o is PeriodOccurrence), isTrue);
      // Oct 1 is a Thursday, so the first week is the clipped tail of the
      // Sep 28 week (4 governed days -> target 2). Every later week is whole.
      expect(out.map((o) => o.target).toList(), [2, 3, 3, 3, 3]);
      expect(out.cast<PeriodOccurrence>().where((o) => o.isClipped), hasLength(1));
    });

    test('the changeover week keeps each side under its own version', () {
      // Sep 28-30 are daily under v1; Oct 1-4 are the clipped tail of the
      // weekly period under v2. Nothing is dropped, nothing double-counted.
      final out = run(
        schedules: versioned(),
        from: d(2026, 9, 28),
        to: d(2026, 10, 4),
      );
      final daily = out.whereType<DailyOccurrence>().toList();
      final periods = out.whereType<PeriodOccurrence>().toList();
      expect(daily.map((o) => o.date).toList(),
          [d(2026, 9, 28), d(2026, 9, 29), d(2026, 9, 30)]);
      expect(periods, hasLength(1));

      final clipped = periods.single;
      expect(clipped.period, CivilDateRange(d(2026, 9, 28), d(2026, 10, 4)));
      expect(clipped.effective, CivilDateRange(d(2026, 10, 1), d(2026, 10, 4)));
      expect(clipped.isClipped, isTrue);
      // 3 per 7 days, prorated over the 4 governed days.
      expect(clipped.target, 2);
    });

    test('a clipped target is never prorated below one', () {
      final out = run(
        schedules: [
          schedule(
            id: 'v1',
            frequency: const Frequency.daily(),
            from: d(2026, 8, 1),
            to: d(2026, 8, 29),
          ),
          schedule(
            id: 'v2',
            frequency: const Frequency.timesPerWeek(target: 4),
            from: d(2026, 8, 30),
          ),
        ],
        from: d(2026, 8, 30),
        to: d(2026, 8, 30),
      );
      // Aug 30 is a Sunday: one governed day out of seven. 4/7 rounds to 1.
      final clipped = out.whereType<PeriodOccurrence>().single;
      expect(clipped.effective, CivilDateRange(d(2026, 8, 30), d(2026, 8, 30)));
      expect(clipped.target, 1);
    });

    test('an unclipped period keeps its full target', () {
      final out = run(
        schedules: versioned(),
        from: d(2026, 10, 5),
        to: d(2026, 10, 11),
      );
      final p = out.whereType<PeriodOccurrence>().single;
      expect(p.isClipped, isFalse);
      expect(p.target, 3);
    });

    test('adding a later version never changes an earlier month', () {
      final before = run(
        schedules: [
          schedule(
            id: 'v1',
            frequency: const Frequency.daily(),
            from: d(2026, 8, 1),
          ),
        ],
        from: d(2026, 8, 1),
        to: d(2026, 8, 31),
      );
      final after =
          run(schedules: versioned(), from: d(2026, 8, 1), to: d(2026, 8, 31));
      expect(after.length, before.length);
      expect(
        after.cast<DailyOccurrence>().map((o) => o.date),
        before.cast<DailyOccurrence>().map((o) => o.date),
      );
    });
  });

  group('pauses', () {
    test('paused days produce no expectation at all', () {
      final out = run(
        schedules: [
          schedule(frequency: const Frequency.daily(), from: d(2026, 8, 1)),
        ],
        pauses: [pause(d(2026, 8, 26), d(2026, 8, 28))],
        from: d(2026, 8, 24),
        to: d(2026, 8, 30),
      );
      expect(
        out.cast<DailyOccurrence>().map((o) => o.date).toList(),
        [d(2026, 8, 24), d(2026, 8, 25), d(2026, 8, 29), d(2026, 8, 30)],
      );
    });

    test('a partially paused period still counts', () {
      final out = run(
        schedules: [
          schedule(
            frequency: const Frequency.timesPerWeek(target: 4),
            from: d(2026, 8, 1),
          ),
        ],
        pauses: [pause(d(2026, 8, 26), d(2026, 8, 27))],
        from: d(2026, 8, 24),
        to: d(2026, 8, 30),
      );
      expect(out, hasLength(1));
    });

    test('a fully paused period drops out entirely', () {
      final out = run(
        schedules: [
          schedule(
            frequency: const Frequency.timesPerWeek(target: 4),
            from: d(2026, 8, 1),
          ),
        ],
        pauses: [pause(d(2026, 8, 24), d(2026, 8, 30))],
        from: d(2026, 8, 24),
        to: d(2026, 8, 30),
      );
      expect(out, isEmpty);
    });
  });
}
