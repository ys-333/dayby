import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/domain/accounting/resolved_occurrence.dart';
import 'package:riyaz/domain/analytics/analytics_engine.dart';
import 'package:riyaz/domain/analytics/consistency_summary.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/pause_period.dart';
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


/// The commitment's open-ended pause, if it has one.
///
/// A separate stream rather than a field on [CommitmentDetail], for the same
/// reason `currentFrequency` is a separate read: the detail stream reports
/// *resolved history*, which has no business carrying the schedule or the
/// pause table, and widening `ResolvedHistory` for one menu label would make
/// history, analytics and insights all pay for a field only this screen looks
/// at.
///
/// The range is a single day because pauses are never filtered by date —
/// `TrackingRepository.read` loads the whole table on every call, so the
/// narrowest possible window still sees every pause, including one that
/// started years ago.
@riverpod
Stream<PausePeriod?> openPause(Ref ref, String commitmentId) {
  final today = ref.watch(todayProvider);
  return ref
      .watch(trackingRepositoryProvider)
      .watch(CivilDateRange(today, today))
      .map((snapshot) {
    for (final pause in snapshot.pausesFor(commitmentId)) {
      if (pause.isOpen) return pause;
    }
    return null;
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

  /// Suspends the commitment from today, with no end date.
  ///
  /// Open-ended on purpose: the honest answer to "how long?" is usually "I
  /// don't know yet", and making the user commit to a return date turns a
  /// pause into a second thing to be late for.
  ///
  /// Paused days are NOT_EXPECTED — the recurrence engine emits no occurrence
  /// for them, so they can never turn MISSED. That is the whole point, and it
  /// is why this writes a `PausePeriod` rather than setting
  /// `CommitmentState.paused`, which nothing in `lib/domain/` reads.
  Future<void> pause(String commitmentId) =>
      repository.pauseCommitment(commitmentId: commitmentId, from: today);

  /// Ends the open pause. Today is expected again; yesterday was not.
  ///
  /// Returns the day the pause began, which is what [restorePause] needs to
  /// put it back.
  Future<CivilDate?> resume(String commitmentId) =>
      repository.resumeCommitment(commitmentId: commitmentId, on: today);

  /// Undo for [resume]: reopens a pause covering the same days again.
  ///
  /// A new row with a new id, not a resurrection of the old one. The user is
  /// undoing a *state* — "I am still paused" — and the identity of the record
  /// carrying it is not something they can see or care about.
  Future<void> restorePause(String commitmentId, CivilDate from) =>
      repository.pauseCommitment(commitmentId: commitmentId, from: from);

  /// Undo for [pause]: resuming on the same day the pause began leaves it
  /// covering no day at all, and the repository deletes it rather than storing
  /// an end that precedes its own start.
  Future<void> cancelPause(String commitmentId, CivilDate from) =>
      repository.resumeCommitment(commitmentId: commitmentId, on: from);

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
    bool clearIcon = false,
    Frequency? frequency,
  }) =>
      repository.updateCommitment(
        commitmentId: commitmentId,
        on: today,
        name: name,
        icon: icon,
        clearIcon: clearIcon,
        frequency: frequency,
      );
}

@riverpod
CommitmentActions commitmentActions(Ref ref) => CommitmentActions(
      repository: ref.watch(trackingRepositoryProvider),
      today: ref.watch(todayProvider),
    );
