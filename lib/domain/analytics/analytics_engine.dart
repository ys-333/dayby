import '../accounting/occurrence_status.dart';
import '../accounting/resolved_occurrence.dart';
import '../time/civil_date.dart';
import 'consistency_summary.dart';

/// A consistency reading for one date, used for trend lines.
class TrendPoint {
  const TrendPoint(this.date, this.consistency);

  final CivilDate date;

  /// Null where the window held nothing eligible — a gap in the line, not a
  /// zero. Charts must not draw these as failure.
  final double? consistency;

  @override
  String toString() => '${date.iso}: ${consistency ?? '—'}';
}

/// Derives every headline number from resolved occurrences.
///
/// Formulas live here and nowhere else. A screen that computes its own
/// consistency is a bug, because two places will disagree eventually.
class AnalyticsEngine {
  const AnalyticsEngine();

  ConsistencySummary summarize(Iterable<ResolvedOccurrence> resolved) =>
      ConsistencySummary.of(resolved);

  /// Momentum over daily-shaped occurrences, oldest first.
  ///
  /// Rules, all of which follow from "describe behaviour, do not judge it":
  ///
  /// - [OccurrenceStatus.done] extends a run.
  /// - [OccurrenceStatus.missed] and [OccurrenceStatus.partial] end one. A
  ///   streak counts completions; calling a shortfall a completion would make
  ///   the number decorative.
  /// - Skipped, paused and unscheduled days are *transparent*: they neither
  ///   extend nor break a run. Skipping a day for travel is not a failure, so
  ///   it must not cost the streak that surrounds it.
  /// - Pending occurrences are ignored entirely. Today has not happened yet,
  ///   and an unfinished today must never break yesterday's run.
  StreakSummary streaks(List<ResolvedOccurrence> ordered) {
    final runs = <int>[];
    final gaps = <int>[];

    var run = 0;
    var gap = 0;
    var sawFirstRun = false;

    for (final r in ordered) {
      switch (r.status) {
        case OccurrenceStatus.skipped:
        case OccurrenceStatus.paused:
        case OccurrenceStatus.notScheduled:
        case OccurrenceStatus.pending:
          continue;

        case OccurrenceStatus.done:
          if (gap > 0 && sawFirstRun) {
            gaps.add(gap);
            gap = 0;
          }
          gap = 0;
          run++;
          sawFirstRun = true;

        case OccurrenceStatus.missed:
        case OccurrenceStatus.partial:
          if (run > 0) {
            runs.add(run);
            run = 0;
          }
          if (sawFirstRun) gap++;
      }
    }

    final current = run;
    final allRuns = [...runs, if (run > 0) run];
    final longest =
        allRuns.isEmpty ? 0 : allRuns.reduce((a, b) => a > b ? a : b);
    final averageStreak = allRuns.isEmpty
        ? 0.0
        : allRuns.reduce((a, b) => a + b) / allRuns.length;
    final averageRecovery = gaps.isEmpty
        ? null
        : gaps.reduce((a, b) => a + b) / gaps.length;

    return StreakSummary(
      current: current,
      longest: longest,
      averageStreak: averageStreak,
      averageRecoveryDays: averageRecovery,
      completedRuns: runs.length,
    );
  }

  /// Rolling consistency across [range], each point covering the [window] days
  /// ending on that date.
  ///
  /// The spec asks for this rather than raw daily values because a binary
  /// per-day series is visual noise — it says nothing about whether behaviour
  /// is trending up. An occurrence joins a window when its span *ends* inside
  /// it, which lets weekly and monthly targets contribute on the day they were
  /// finally judged instead of smearing across the chart.
  List<TrendPoint> rollingConsistency({
    required List<ResolvedOccurrence> resolved,
    required CivilDateRange range,
    int window = 7,
  }) {
    final byEndDate = <int, List<ResolvedOccurrence>>{};
    for (final r in resolved) {
      byEndDate.putIfAbsent(r.occurrence.span.end.epochDay, () => []).add(r);
    }

    return [
      for (final date in range.dates)
        TrendPoint(
          date,
          ConsistencySummary.of([
            for (var back = 0; back < window; back++)
              ...?byEndDate[date.epochDay - back],
          ]).consistency,
        ),
    ];
  }

  /// Consistency per calendar bucket, for the month and year screens.
  ///
  /// [bucketOf] chooses the bucket a date belongs to; buckets come back in
  /// chronological order. Buckets that are entirely in the future never appear,
  /// because [resolved] holds no occurrences for them.
  Map<CivilDate, ConsistencySummary> bucketed({
    required List<ResolvedOccurrence> resolved,
    required CivilDate Function(CivilDate) bucketOf,
  }) {
    final groups = <CivilDate, List<ResolvedOccurrence>>{};
    for (final r in resolved) {
      groups.putIfAbsent(bucketOf(r.occurrence.span.end), () => []).add(r);
    }
    final keys = groups.keys.toList()..sort();
    return {for (final k in keys) k: ConsistencySummary.of(groups[k]!)};
  }
}
