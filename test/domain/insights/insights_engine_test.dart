import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/accounting/resolved_occurrence.dart';
import 'package:riyaz/domain/analytics/analytics_engine.dart';
import 'package:riyaz/domain/analytics/scoring.dart';
import 'package:riyaz/domain/insights/insight.dart';
import 'package:riyaz/domain/insights/insights_engine.dart';
import 'package:riyaz/domain/recurrence/expected_occurrence.dart';
import 'package:riyaz/domain/time/accounting_calendar.dart';
import 'package:riyaz/domain/time/civil_date.dart';

import '../../support/dates.dart';
import '../../support/fixtures.dart';

ResolvedOccurrence day(CivilDate date, OccurrenceStatus status) =>
    resolutionOf(
      occurrence: DailyOccurrence(
        commitmentId: commitmentId,
        date: date,
        target: 1,
      ),
      status: status,
      completed: status == OccurrenceStatus.done ? 1 : 0,
      weights: ScoringWeights.standard,
    );

/// Builds a run of statuses starting at [from].
List<ResolvedOccurrence> run(
  CivilDate from,
  OccurrenceStatus status,
  int count,
) =>
    [for (var i = 0; i < count; i++) day(from.plusDays(i), status)];

void main() {
  const engine = InsightsEngine();
  const analytics = AnalyticsEngine();
  final start = d(2026, 1, 5); // a Monday

  InsightsResult generate(
    List<ResolvedOccurrence> resolved, {
    int activeDaily = 1,
  }) =>
      engine.generate(
        resolved: resolved,
        streaks: analytics.streaks(resolved),
        activeDailyCommitments: activeDaily,
      );

  group('data thresholds', () {
    test('says so rather than inventing a pattern', () {
      final result = generate(run(start, OccurrenceStatus.done, 10));
      expect(result.hasEnoughData, isFalse);
      expect(result.eligibleObservations, 10);
      expect(result.requiredObservations, 21);
      expect(
        result.insights.where((i) => i.kind != InsightKind.load),
        isEmpty,
        reason: 'no behavioural claim may be made below the threshold',
      );
    });

    test('pending and skipped days do not count toward the threshold', () {
      final resolved = [
        ...run(start, OccurrenceStatus.done, 5),
        ...run(start.plusDays(5), OccurrenceStatus.skipped, 20),
        ...run(start.plusDays(25), OccurrenceStatus.pending, 20),
      ];
      expect(generate(resolved).hasEnoughData, isFalse);
    });

    test('crosses the threshold once enough is eligible', () {
      expect(
        generate(run(start, OccurrenceStatus.done, 21)).hasEnoughData,
        isTrue,
      );
    });
  });

  group('momentum', () {
    /// Three complete cycles of five done then two missed.
    List<ResolvedOccurrence> cycles() {
      final out = <ResolvedOccurrence>[];
      var cursor = start;
      for (var i = 0; i < 4; i++) {
        out.addAll(run(cursor, OccurrenceStatus.done, 5));
        cursor = cursor.plusDays(5);
        out.addAll(run(cursor, OccurrenceStatus.missed, 2));
        cursor = cursor.plusDays(2);
      }
      return out;
    }

    test('reports run length only after repeated cycles', () {
      final few = [
        ...run(start, OccurrenceStatus.done, 20),
        ...run(start.plusDays(20), OccurrenceStatus.missed, 2),
      ];
      expect(
        generate(few).insights.where((i) => i.kind == InsightKind.momentum),
        isEmpty,
        reason: 'one run is not a pattern',
      );

      final many = generate(cycles());
      final momentum =
          many.insights.firstWhere((i) => i.kind == InsightKind.momentum);
      expect(momentum.headline, contains('5.0 days'));
    });

    test('reports recovery once a lapse has actually been recovered from', () {
      final recovery = generate(cycles())
          .insights
          .firstWhere((i) => i.kind == InsightKind.recovery);
      expect(recovery.headline, contains('2.0 days'));
    });

    test('an unrecovered lapse yields no recovery claim', () {
      final resolved = [
        ...run(start, OccurrenceStatus.done, 25),
        ...run(start.plusDays(25), OccurrenceStatus.missed, 5),
      ];
      expect(
        generate(resolved).insights.where((i) => i.kind == InsightKind.recovery),
        isEmpty,
      );
    });
  });

  group('weekday patterns', () {
    test('names the weakest day when the gap is real', () {
      // Every Sunday missed, everything else done, over six weeks.
      final resolved = <ResolvedOccurrence>[];
      for (var i = 0; i < 42; i++) {
        final date = start.plusDays(i);
        resolved.add(day(
          date,
          date.weekday == DateTime.sunday
              ? OccurrenceStatus.missed
              : OccurrenceStatus.done,
        ));
      }

      final insight = generate(resolved)
          .insights
          .firstWhere((i) => i.kind == InsightKind.dayOfWeek);
      expect(insight.headline, contains('Sunday'));
      expect(insight.detail, contains('0%'));
    });

    test('stays quiet when every day looks the same', () {
      final resolved = [
        for (var i = 0; i < 42; i++)
          day(start.plusDays(i), OccurrenceStatus.done),
      ];
      expect(
        generate(resolved)
            .insights
            .where((i) => i.kind == InsightKind.dayOfWeek),
        isEmpty,
        reason: 'a flat distribution is not a finding',
      );
    });

    test('ignores period occurrences, which have no weekday', () {
      final periods = [
        for (var i = 0; i < 8; i++)
          resolutionOf(
            occurrence: PeriodOccurrence(
              commitmentId: commitmentId,
              scope: PeriodScope.weekly,
              period: CivilDateRange(
                start.plusDays(i * 7),
                start.plusDays(i * 7 + 6),
              ),
              target: 4,
            ),
            status: OccurrenceStatus.missed,
            completed: 0,
            weights: ScoringWeights.standard,
          ),
      ];
      expect(engine.weekdayBreakdown(periods), isEmpty);
    });

    test('a weekday below the sample floor is not judged', () {
      // Two weeks only, so each weekday has exactly two samples — under the
      // floor of three, so no weekday may be named however lopsided it looks.
      final resolved = [
        for (var i = 0; i < 14; i++)
          day(
            start.plusDays(i),
            start.plusDays(i).weekday == DateTime.sunday
                ? OccurrenceStatus.missed
                : OccurrenceStatus.done,
          ),
      ];
      expect(engine.weekdayBreakdown(resolved)[DateTime.sunday]!.eligible, 2);
      expect(
        generate(resolved)
            .insights
            .where((i) => i.kind == InsightKind.dayOfWeek),
        isEmpty,
      );
    });
  });

  group('commitment load', () {
    test('warns at the soft cap regardless of history', () {
      final result = generate(const [], activeDaily: 6);
      final load =
          result.insights.firstWhere((i) => i.kind == InsightKind.load);
      expect(load.headline, contains('6 active daily'));
      expect(
        result.hasEnoughData,
        isFalse,
        reason: 'the load count is not a behavioural claim',
      );
    });

    test('stays quiet below the cap', () {
      expect(
        generate(const [], activeDaily: 5)
            .insights
            .where((i) => i.kind == InsightKind.load),
        isEmpty,
      );
    });
  });

  test('thresholds are configurable', () {
    const strict = InsightsEngine(
      thresholds: InsightThresholds(minEligibleObservations: 100),
    );
    final result = strict.generate(
      resolved: run(start, OccurrenceStatus.done, 30),
      streaks: analytics.streaks(run(start, OccurrenceStatus.done, 30)),
      activeDailyCommitments: 1,
    );
    expect(result.hasEnoughData, isFalse);
  });
}
