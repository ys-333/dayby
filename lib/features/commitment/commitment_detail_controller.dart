import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/domain/accounting/resolved_occurrence.dart';
import 'package:riyaz/domain/analytics/analytics_engine.dart';
import 'package:riyaz/domain/analytics/consistency_summary.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/model/frequency.dart';
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


/// The writes the detail screen can make.
///
/// Kept beside the read model so the two stay in view of each other: every
/// action here changes something the stream above reports, and a change to one
/// that forgets the other is how a screen starts lying about its own state.
class CommitmentActions {
  const CommitmentActions({required this.repository, required this.today});

  final TrackingRepository repository;
  final CivilDate today;

  /// Takes a commitment out of the daily list without touching its past.
  ///
  /// History before the archive date is preserved exactly — nothing deleted,
  /// no event rewritten. What archiving *does* change is the future: the
  /// schedule is closed on the archive date, so no occurrence is expected
  /// after it and none can turn MISSED.
  ///
  /// That closing is the whole substance of the operation. `lib/domain/` reads
  /// neither `state` nor `archivedOn`, so a version of this that only set the
  /// flag would leave the engine expecting a run every day forever.
  Future<void> archive(String commitmentId) =>
      repository.archiveCommitment(commitmentId, today);

  /// Puts it back in the list and reopens the schedule archiving closed.
  Future<void> unarchive(String commitmentId) =>
      repository.unarchiveCommitment(commitmentId);

  /// The frequency in force today.
  ///
  /// Read on the gesture rather than carried in [CommitmentDetail]: the detail
  /// stream reports resolved history, which has no need of the schedule, and
  /// widening it for one dialog would make every screen that watches it pay
  /// for a field only this sheet reads.
  Future<Frequency?> currentFrequency(String commitmentId) async {
    final snapshot = await repository.read(CivilDateRange(today, today));
    for (final schedule in snapshot.schedulesFor(commitmentId)) {
      final startedYet = schedule.effectiveFrom <= today;
      final stillOpen =
          schedule.effectiveTo == null || today <= schedule.effectiveTo!;
      if (startedYet && stillOpen) return schedule.frequency;
    }
    return null;
  }

  /// Applies an edit. A frequency change takes effect **today**, leaving every
  /// past day judged by the rules it was actually lived under.
  Future<void> edit({
    required String commitmentId,
    String? name,
    String? icon,
    Frequency? frequency,
  }) =>
      repository.updateCommitment(
        commitmentId: commitmentId,
        on: today,
        name: name,
        icon: icon,
        frequency: frequency,
      );
}

@riverpod
CommitmentActions commitmentActions(Ref ref) => CommitmentActions(
      repository: ref.watch(trackingRepositoryProvider),
      today: ref.watch(todayProvider),
    );
