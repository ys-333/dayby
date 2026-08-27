import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/domain/analytics/analytics_engine.dart';
import 'package:riyaz/domain/analytics/consistency_summary.dart';
import 'package:riyaz/domain/insights/insight.dart';
import 'package:riyaz/domain/insights/insights_engine.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/recurrence/expected_occurrence.dart';
import 'package:riyaz/domain/time/civil_date.dart';

part 'insights_controller.g.dart';

class InsightsData {
  const InsightsData({
    required this.last90,
    required this.streaks,
    required this.result,
    required this.months,
    required this.trend,
    required this.activeDailyCommitments,
  });

  final ConsistencySummary last90;
  final StreakSummary streaks;
  final InsightsResult result;

  /// Consistency per month of the current year, read from materialised
  /// rollups rather than re-resolving a year of events on every rebuild.
  final Map<CivilDate, ConsistencySummary> months;

  final List<TrendPoint> trend;
  final int activeDailyCommitments;
}

@Riverpod(keepAlive: true)
InsightsEngine insightsEngine(Ref ref) => const InsightsEngine();

@riverpod
Stream<InsightsData> insightsData(Ref ref) {
  final analytics = ref.watch(analyticsEngineProvider);
  final engine = ref.watch(insightsEngineProvider);
  final rollups = ref.watch(rollupRepositoryProvider);
  final today = ref.watch(todayProvider);

  final window = CivilDateRange(today.plusDays(-179), today);
  final yearRange = CivilDateRange(CivilDate(today.year, 1, 1), today);

  return ref
      .watch(resolutionServiceProvider)
      .watch(window)
      .asyncMap((history) async {
    final active = [
      for (final c in history.commitments)
        if (c.state == CommitmentState.active) c,
    ];

    // A commitment counts against the daily cap when it actually produced a
    // daily expectation — the schedule shape, not the user's intent, decides.
    final activeDaily = active
        .where((c) => history
            .forCommitment(c.id)
            .any((r) => r.occurrence is DailyOccurrence))
        .length;

    final resolved = [
      for (final c in active) ...history.forCommitment(c.id),
    ];

    await rollups.ensureFresh(yearRange);
    final months = await rollups.bucketed(
      range: yearRange,
      bucketOf: (date) => date.startOfMonth,
    );

    final streaks = analytics.streaks(resolved);

    return InsightsData(
      last90: analytics.summarize([
        for (final r in resolved)
          if (r.occurrence.span.end >= today.plusDays(-89)) r,
      ]),
      streaks: streaks,
      result: engine.generate(
        resolved: resolved,
        streaks: streaks,
        activeDailyCommitments: activeDaily,
      ),
      months: months,
      trend: analytics.rollingConsistency(
        resolved: resolved,
        range: CivilDateRange(today.plusDays(-89), today),
      ),
      activeDailyCommitments: activeDaily,
    );
  });
}
