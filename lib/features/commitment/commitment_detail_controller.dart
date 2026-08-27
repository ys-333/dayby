import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/domain/accounting/resolved_occurrence.dart';
import 'package:riyaz/domain/analytics/analytics_engine.dart';
import 'package:riyaz/domain/analytics/consistency_summary.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/time/accounting_calendar.dart';
import 'package:riyaz/domain/time/civil_date.dart';

part 'commitment_detail_controller.g.dart';

/// Everything the detail screen shows, computed once from one resolution pass.
class CommitmentDetail {
  const CommitmentDetail({
    required this.commitment,
    required this.streaks,
    required this.thisWeek,
    required this.thisMonth,
    required this.last90,
    required this.thisYear,
    required this.trend,
    required this.recent,
  });

  final Commitment commitment;
  final StreakSummary streaks;
  final ConsistencySummary thisWeek;
  final ConsistencySummary thisMonth;
  final ConsistencySummary last90;
  final ConsistencySummary thisYear;
  final List<TrendPoint> trend;

  /// Most recent occurrences, newest last, for the strip at the bottom.
  final List<ResolvedOccurrence> recent;
}

@riverpod
Stream<CommitmentDetail?> commitmentDetail(Ref ref, String commitmentId) {
  final calendar = ref.watch(accountingCalendarProvider);
  final analytics = ref.watch(analyticsEngineProvider);
  final today = ref.watch(todayProvider);

  // A year back covers every window the screen reports. One pass, then sliced
  // — resolving four times would risk four subtly different answers.
  final yearStart = CivilDate(today.year, 1, 1);
  final windowStart = today.plusDays(-364);
  final range = CivilDateRange(
    windowStart < yearStart ? windowStart : yearStart,
    today,
  );

  return ref.watch(resolutionServiceProvider).watch(range).map((history) {
    final commitment = history.commitment(commitmentId);
    if (commitment == null) return null;

    final resolved = history.forCommitment(commitmentId);

    List<ResolvedOccurrence> since(CivilDate from) => [
          for (final r in resolved)
            if (r.occurrence.span.end >= from) r,
        ];

    final week = calendar.periodContaining(PeriodScope.weekly, today);
    final month = calendar.periodContaining(PeriodScope.monthly, today);
    final trendRange = CivilDateRange(today.plusDays(-89), today);

    return CommitmentDetail(
      commitment: commitment,
      streaks: analytics.streaks(resolved),
      thisWeek: analytics.summarize(since(week.start)),
      thisMonth: analytics.summarize(since(month.start)),
      last90: analytics.summarize(since(today.plusDays(-89))),
      thisYear: analytics.summarize(since(yearStart)),
      trend: analytics.rollingConsistency(
        resolved: resolved,
        range: trendRange,
      ),
      recent: since(today.plusDays(-34)),
    );
  });
}
