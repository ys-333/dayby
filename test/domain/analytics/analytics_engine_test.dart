import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/accounting/accounting_engine.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/accounting/resolved_occurrence.dart';
import 'package:riyaz/domain/analytics/analytics_engine.dart';
import 'package:riyaz/domain/analytics/scoring.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/recurrence/expected_occurrence.dart';
import 'package:riyaz/domain/recurrence/recurrence_engine.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/domain/time/clock.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/dates.dart';
import '../../support/fixtures.dart';

/// Builds a resolved daily occurrence directly, for summary arithmetic.
ResolvedOccurrence daily(
  CivilDate date,
  OccurrenceStatus status, {
  int completed = 0,
  int target = 1,
}) =>
    resolutionOf(
      occurrence: DailyOccurrence(
        commitmentId: commitmentId,
        date: date,
        target: target,
      ),
      status: status,
      completed: completed,
      weights: ScoringWeights.standard,
    );

List<ResolvedOccurrence> repeat(
  OccurrenceStatus status,
  int n, {
  required int startDay,
}) =>
    [
      for (var i = 0; i < n; i++)
        daily(d(2026, 8, startDay + i), status,
            completed: status == OccurrenceStatus.done ? 1 : 0),
    ];

void main() {
  setUpAll(tzdata.initializeTimeZones);

  const analytics = AnalyticsEngine();

  group('consistency formula', () {
    test("matches the spec's worked example", () {
      // The spec's §49 example states 88.9% from 15 done, 2 partial, 2 skipped
      // and a denominator of 18. Its own counts sum to 20 rather than 18, so we
      // follow the stated *formula* (weighted / eligible, skips excluded) with
      // self-consistent counts, which reproduces the stated answer.
      final resolved = [
        ...repeat(OccurrenceStatus.done, 15, startDay: 1),
        ...repeat(OccurrenceStatus.partial, 2, startDay: 16),
        ...repeat(OccurrenceStatus.missed, 1, startDay: 18),
        ...repeat(OccurrenceStatus.skipped, 2, startDay: 19),
      ];
      final s = analytics.summarize(resolved);

      expect(s.eligible, 18);
      expect(s.weightedCompletion, closeTo(16.0, 1e-9));
      expect(s.consistency, closeTo(0.8889, 1e-4));
      expect(s.percent, 89);
      expect(s.skipped, 2);
    });

    test('skips leave the denominator rather than scoring zero', () {
      final withSkips = analytics.summarize([
        ...repeat(OccurrenceStatus.done, 3, startDay: 1),
        ...repeat(OccurrenceStatus.skipped, 5, startDay: 4),
      ]);
      expect(withSkips.eligible, 3);
      expect(withSkips.percent, 100);
    });

    test('pending is excluded, so today cannot lower the score', () {
      final s = analytics.summarize([
        ...repeat(OccurrenceStatus.done, 4, startDay: 1),
        ...repeat(OccurrenceStatus.pending, 10, startDay: 5),
      ]);
      expect(s.eligible, 4);
      expect(s.pending, 10);
      expect(s.percent, 100);
    });

    test('a missed day counts as zero but stays in the denominator', () {
      final s = analytics.summarize([
        ...repeat(OccurrenceStatus.done, 3, startDay: 1),
        ...repeat(OccurrenceStatus.missed, 1, startDay: 4),
      ]);
      expect(s.eligible, 4);
      expect(s.percent, 75);
    });

    test('no eligible occurrences yields null, never zero', () {
      expect(analytics.summarize(const []).consistency, isNull);
      expect(analytics.summarize(const []).percent, isNull);
      expect(
        analytics.summarize(repeat(OccurrenceStatus.pending, 3, startDay: 1))
            .consistency,
        isNull,
      );
    });

    test('paused and unscheduled contribute nothing at all', () {
      final s = analytics.summarize([
        ...repeat(OccurrenceStatus.done, 2, startDay: 1),
        ...repeat(OccurrenceStatus.paused, 4, startDay: 3),
        ...repeat(OccurrenceStatus.notScheduled, 4, startDay: 7),
      ]);
      expect(s.eligible, 2);
      expect(s.percent, 100);
    });

    test('partial credit is half of a completion', () {
      final s = analytics.summarize([
        ...repeat(OccurrenceStatus.partial, 2, startDay: 1),
      ]);
      expect(s.weightedCompletion, closeTo(1.0, 1e-9));
      expect(s.percent, 50);
    });
  });

  group('streaks and recovery', () {
    test("the spec's scenario: five done, three missed, one back", () {
      final calendar = calendarFor('Asia/Kolkata');
      final engine = AccountingEngine(
        calendar: calendar,
        recurrence: RecurrenceEngine(calendar),
      );
      final done = [1, 2, 3, 4, 5, 9];
      final resolved = engine.resolveRange(
        commitmentId: commitmentId,
        schedules: [
          schedule(frequency: const Frequency.daily(), from: d(2026, 8, 1)),
        ],
        pauses: const [],
        events: [for (final day in done) event(d(2026, 8, day), id: 'e$day')],
        range: CivilDateRange(d(2026, 8, 1), d(2026, 8, 9)),
        clock: FixedClock.iso('2026-08-10T10:00:00+05:30'),
      );

      final s = analytics.streaks(resolved);
      expect(s.longest, 5);
      expect(s.current, 1);
      expect(s.averageRecoveryDays, 3.0);
      expect(s.completedRuns, 1);
    });

    test('a skipped day is transparent and does not break a run', () {
      final s = analytics.streaks([
        ...repeat(OccurrenceStatus.done, 3, startDay: 1),
        ...repeat(OccurrenceStatus.skipped, 2, startDay: 4),
        ...repeat(OccurrenceStatus.done, 3, startDay: 6),
      ]);
      expect(s.current, 6);
      expect(s.longest, 6);
    });

    test('an unfinished today does not break yesterday\'s run', () {
      final s = analytics.streaks([
        ...repeat(OccurrenceStatus.done, 5, startDay: 1),
        ...repeat(OccurrenceStatus.pending, 1, startDay: 6),
      ]);
      expect(s.current, 5);
    });

    test('a partial ends a run — a streak counts completions', () {
      final s = analytics.streaks([
        ...repeat(OccurrenceStatus.done, 4, startDay: 1),
        ...repeat(OccurrenceStatus.partial, 1, startDay: 5),
        ...repeat(OccurrenceStatus.done, 1, startDay: 6),
      ]);
      expect(s.longest, 4);
      expect(s.current, 1);
    });

    test('recovery averages across multiple lapses', () {
      final s = analytics.streaks([
        ...repeat(OccurrenceStatus.done, 3, startDay: 1),
        ...repeat(OccurrenceStatus.missed, 2, startDay: 4),
        ...repeat(OccurrenceStatus.done, 3, startDay: 6),
        ...repeat(OccurrenceStatus.missed, 4, startDay: 9),
        ...repeat(OccurrenceStatus.done, 2, startDay: 13),
      ]);
      expect(s.averageRecoveryDays, 3.0); // (2 + 4) / 2
      expect(s.completedRuns, 2);
      expect(s.longest, 3);
      expect(s.current, 2);
    });

    test('an open lapse has no recovery time yet', () {
      final s = analytics.streaks([
        ...repeat(OccurrenceStatus.done, 3, startDay: 1),
        ...repeat(OccurrenceStatus.missed, 4, startDay: 4),
      ]);
      expect(s.averageRecoveryDays, isNull);
      expect(s.current, 0);
      expect(s.longest, 3);
    });

    test('leading misses are not counted as a recovery gap', () {
      // Nothing to recover from before the first run.
      final s = analytics.streaks([
        ...repeat(OccurrenceStatus.missed, 3, startDay: 1),
        ...repeat(OccurrenceStatus.done, 2, startDay: 4),
      ]);
      expect(s.averageRecoveryDays, isNull);
      expect(s.current, 2);
    });

    test('an empty history is all zeroes, not an error', () {
      final s = analytics.streaks(const []);
      expect(s.current, 0);
      expect(s.longest, 0);
      expect(s.averageRecoveryDays, isNull);
    });
  });

  group('rolling consistency', () {
    test('averages over the trailing window', () {
      final resolved = [
        ...repeat(OccurrenceStatus.done, 7, startDay: 1),
        ...repeat(OccurrenceStatus.missed, 7, startDay: 8),
      ];
      final points = analytics.rollingConsistency(
        resolved: resolved,
        range: CivilDateRange(d(2026, 8, 7), d(2026, 8, 14)),
      );

      // Aug 7 closes a fully-done week.
      expect(points.first.consistency, closeTo(1.0, 1e-9));
      // Aug 14 closes a fully-missed week.
      expect(points.last.consistency, closeTo(0.0, 1e-9));
      // The middle slopes down monotonically.
      final values = points.map((p) => p.consistency!).toList();
      for (var i = 1; i < values.length; i++) {
        expect(values[i], lessThanOrEqualTo(values[i - 1]));
      }
    });

    test('a window with nothing eligible is a gap, not a zero', () {
      final points = analytics.rollingConsistency(
        resolved: repeat(OccurrenceStatus.pending, 3, startDay: 1),
        range: CivilDateRange(d(2026, 8, 1), d(2026, 8, 3)),
      );
      expect(points.every((p) => p.consistency == null), isTrue);
    });
  });

  group('bucketed consistency', () {
    test('groups by month in chronological order', () {
      final resolved = [
        ...repeat(OccurrenceStatus.done, 4, startDay: 1),
        daily(d(2026, 9, 1), OccurrenceStatus.missed),
        daily(d(2026, 9, 2), OccurrenceStatus.done, completed: 1),
      ];
      final months = analytics.bucketed(
        resolved: resolved,
        bucketOf: (date) => date.startOfMonth,
      );
      expect(months.keys.toList(), [d(2026, 8, 1), d(2026, 9, 1)]);
      expect(months[d(2026, 8, 1)]!.percent, 100);
      expect(months[d(2026, 9, 1)]!.percent, 50);
    });
  });
}
