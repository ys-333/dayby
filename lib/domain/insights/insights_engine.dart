import '../accounting/occurrence_status.dart';
import '../accounting/resolved_occurrence.dart';
import '../analytics/consistency_summary.dart';
import '../recurrence/expected_occurrence.dart';
import 'insight.dart';

/// How much history an insight needs before it is allowed to exist.
class InsightThresholds {
  const InsightThresholds({
    this.minEligibleObservations = 21,
    this.minCompletedRuns = 3,
    this.minPerWeekdaySamples = 3,
    this.dailyCommitmentSoftCap = 6,
    this.weekdaySpread = 0.25,
  });

  static const InsightThresholds standard = InsightThresholds();

  /// Roughly three weeks of eligible occurrences before any pattern claim.
  final int minEligibleObservations;

  /// Momentum claims need repeated cycles, not one lucky run.
  final int minCompletedRuns;

  /// A weekday needs this many samples before it can be called strong or weak.
  final int minPerWeekdaySamples;

  final int dailyCommitmentSoftCap;

  /// Minimum gap between best and worst weekday before it is worth mentioning.
  /// Without it, noise in a small sample reads as a discovery.
  final double weekdaySpread;
}

/// Rule-based observations over resolved history.
///
/// No model, no inference, no LLM — every statement here is a direct reading of
/// counted behaviour, and any of them can be checked by hand. That is the point:
/// insights that cannot be verified cannot be trusted, and a tracker that
/// invents patterns teaches the user to ignore it.
class InsightsEngine {
  const InsightsEngine({this.thresholds = InsightThresholds.standard});

  final InsightThresholds thresholds;

  InsightsResult generate({
    required List<ResolvedOccurrence> resolved,
    required StreakSummary streaks,
    required int activeDailyCommitments,
  }) {
    final summary = ConsistencySummary.of(resolved);
    final insights = <Insight>[];

    // The load warning is not a pattern claim — it is a count of what exists
    // right now, so it is exempt from the history threshold.
    if (activeDailyCommitments >= thresholds.dailyCommitmentSoftCap) {
      insights.add(Insight(
        kind: InsightKind.load,
        headline: '$activeDailyCommitments active daily commitments',
        detail: 'That is a lot to hold at once. Consider trimming the list.',
      ));
    }

    if (summary.eligible < thresholds.minEligibleObservations) {
      return InsightsResult(
        insights: insights,
        hasEnoughData: false,
        eligibleObservations: summary.eligible,
        requiredObservations: thresholds.minEligibleObservations,
      );
    }

    if (streaks.completedRuns >= thresholds.minCompletedRuns) {
      final average = streaks.averageStreak;
      insights.add(Insight(
        kind: InsightKind.momentum,
        headline:
            'Your runs last about ${average.toStringAsFixed(average >= 10 ? 0 : 1)} days',
        detail: 'Longest so far: ${streaks.longest} days.',
      ));

      final recovery = streaks.averageRecoveryDays;
      if (recovery != null) {
        insights.add(Insight(
          kind: InsightKind.recovery,
          headline:
              'You come back within ${recovery.toStringAsFixed(recovery >= 10 ? 0 : 1)} days',
          detail: 'Recovering quickly matters more than never slipping.',
        ));
      }
    }

    final weekday = _weekdayInsight(resolved);
    if (weekday != null) insights.add(weekday);

    return InsightsResult(
      insights: insights,
      hasEnoughData: true,
      eligibleObservations: summary.eligible,
      requiredObservations: thresholds.minEligibleObservations,
    );
  }

  /// Consistency per weekday, over daily occurrences only.
  ///
  /// Period targets are excluded deliberately: a 4x/week commitment has no
  /// opinion about Tuesday, so folding it in would attribute behaviour to days
  /// that were never individually expected.
  Map<int, ConsistencySummary> weekdayBreakdown(
    List<ResolvedOccurrence> resolved,
  ) {
    final groups = <int, List<ResolvedOccurrence>>{};
    for (final r in resolved) {
      if (r.occurrence is PeriodOccurrence) continue;
      if (!r.status.isEligible) continue;
      groups.putIfAbsent(r.occurrence.span.start.weekday, () => []).add(r);
    }
    return {
      for (final entry in groups.entries)
        entry.key: ConsistencySummary.of(entry.value),
    };
  }

  Insight? _weekdayInsight(List<ResolvedOccurrence> resolved) {
    final byWeekday = weekdayBreakdown(resolved);
    final usable = {
      for (final e in byWeekday.entries)
        if (e.value.eligible >= thresholds.minPerWeekdaySamples &&
            e.value.consistency != null)
          e.key: e.value.consistency!,
    };
    if (usable.length < 4) return null;

    final sorted = usable.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = sorted.first;
    final worst = sorted.last;

    // Without a real gap, this is sampling noise dressed up as a finding.
    if (best.value - worst.value < thresholds.weekdaySpread) return null;

    return Insight(
      kind: InsightKind.dayOfWeek,
      headline: '${_weekdayName(worst.key)} is your weakest day',
      detail: '${(worst.value * 100).round()}% there, against '
          '${(best.value * 100).round()}% on ${_weekdayName(best.key)}.',
    );
  }

  String _weekdayName(int weekday) => const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][weekday - 1];
}
