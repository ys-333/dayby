import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/domain/accounting/resolved_occurrence.dart';
import 'package:riyaz/domain/analytics/analytics_engine.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/analytics/consistency_summary.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/pause_period.dart';
import 'package:riyaz/domain/recurrence/expected_occurrence.dart';
import 'package:riyaz/domain/time/accounting_calendar.dart';
import 'package:riyaz/domain/time/civil_date.dart';

part 'commitment_detail_controller.g.dart';

/// Columns in the twelve-week grid.
///
/// Twelve rather than the year the screen already resolves: at 390dp a
/// fifty-two-week grid gives each day about four pixels, which is a texture
/// rather than a record. Twelve weeks is a season — long enough to show a
/// rhythm, short enough that a single day is still a thing you can point at.
const int _gridWeeks = 12;

/// The newest note in [resolved], or null if the user has never written one.
DatedNote? _latestNote(List<ResolvedOccurrence> resolved) {
  ResolvedOccurrence? newest;
  for (final r in resolved) {
    final note = r.note;
    if (note == null || note.isEmpty) continue;
    if (newest == null || r.occurrence.span.end > newest.occurrence.span.end) {
      newest = r;
    }
  }
  return newest == null
      ? null
      : DatedNote(text: newest.note!, date: newest.occurrence.span.end);
}

/// One day in the twelve-week grid.
class GridDay {
  const GridDay({
    required this.date,
    required this.status,
    required this.creditedToPeriod,
    required this.isFuture,
  });

  final CivilDate date;

  /// Null when the schedule expected nothing that day — before the commitment
  /// started, on an off day, or inside a pause.
  final OccurrenceStatus? status;

  /// A completion for a **period** target landed on this day.
  ///
  /// Drawn as a mark of its own, never as a status. A 4x-a-week target has no
  /// opinion about which days it is met on, so painting a credited day as
  /// "done" would claim that day was owed — the exact misconception the period
  /// model exists to prevent. Same rule, and the same two shapes, as the week
  /// grid on the history screen.
  final bool creditedToPeriod;

  /// Not lived yet. Never drawn as a failure.
  final bool isFuture;
}

/// The most recent note the user wrote, and the day it belongs to.
class DatedNote {
  const DatedNote({required this.text, required this.date});

  final String text;
  final CivilDate date;
}

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
    required this.grid,
    required this.gridStart,
    required this.isPeriod,
    required this.periodLabel,
    required this.latestNote,
  });

  final Commitment commitment;
  final StreakSummary streaks;
  final ConsistencySummary thisWeek;
  final ConsistencySummary thisMonth;
  final ConsistencySummary last90;
  final ConsistencySummary thisYear;
  final List<TrendPoint> trend;

  /// Twelve whole weeks ending with the current one, oldest first, aligned so
  /// that every seventh entry starts a new week.
  ///
  /// Replaces the thirty undated circles the screen used to end with. Those
  /// showed a sequence with no dates on it, which meant a gap could not be
  /// placed and therefore could not be learned from. A dated grid answers
  /// "when do I drop this?" — which is the only question the strip was ever
  /// being asked.
  final List<GridDay> grid;

  /// First day of [grid] — a week start, so the grid's rows are weekdays.
  final CivilDate gridStart;

  /// True when this commitment is scored over a week or a month rather than a
  /// day. Changes what the grid's marks *mean*, so it travels with them.
  final bool isPeriod;

  /// "a week" / "a month" for a period commitment, else null.
  final String? periodLabel;

  final DatedNote? latestNote;
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

    // Twelve whole weeks, the current one last. Anchored to the week start so
    // every row of the rendered grid is one weekday — a grid anchored to
    // "today minus 83" would put a different weekday in each row and destroy
    // the one pattern it exists to show.
    final gridStart = calendar
        .startOfWeek(today)
        .plusDays(-7 * (_gridWeeks - 1));

    final byDay = <int, ResolvedOccurrence>{};
    final credited = <int>{};
    PeriodOccurrence? anyPeriod;

    for (final r in resolved) {
      final occurrence = r.occurrence;
      if (occurrence is PeriodOccurrence) {
        anyPeriod = occurrence;
        for (final day in r.creditedDays) {
          credited.add(day.epochDay);
        }
      } else {
        byDay[occurrence.span.start.epochDay] = r;
      }
    }

    final grid = [
      for (var i = 0; i < _gridWeeks * 7; i++)
        () {
          final date = gridStart.plusDays(i);
          return GridDay(
            date: date,
            status: byDay[date.epochDay]?.status,
            creditedToPeriod: credited.contains(date.epochDay),
            isFuture: date > today,
          );
        }(),
    ];

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
      grid: grid,
      gridStart: gridStart,
      isPeriod: anyPeriod != null,
      periodLabel: switch (anyPeriod?.scope) {
        PeriodScope.weekly => 'a week',
        PeriodScope.monthly => 'a month',
        _ => null,
      },
      latestNote: _latestNote(resolved),
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
