import '../accounting/occurrence_status.dart';
import '../accounting/resolved_occurrence.dart';

/// Counts and score for a set of resolved occurrences.
class ConsistencySummary {
  const ConsistencySummary({
    required this.done,
    required this.partial,
    required this.missed,
    required this.skipped,
    required this.pending,
    required this.weightedCompletion,
  });

  factory ConsistencySummary.of(Iterable<ResolvedOccurrence> resolved) {
    var done = 0, partial = 0, missed = 0, skipped = 0, pending = 0;
    var weighted = 0.0;
    for (final r in resolved) {
      switch (r.status) {
        case OccurrenceStatus.done:
          done++;
        case OccurrenceStatus.partial:
          partial++;
        case OccurrenceStatus.missed:
          missed++;
        case OccurrenceStatus.skipped:
          skipped++;
        case OccurrenceStatus.pending:
          pending++;
        case OccurrenceStatus.paused:
        case OccurrenceStatus.notScheduled:
          break;
      }
      weighted += r.credit;
    }
    return ConsistencySummary(
      done: done,
      partial: partial,
      missed: missed,
      skipped: skipped,
      pending: pending,
      weightedCompletion: weighted,
    );
  }

  static const ConsistencySummary empty = ConsistencySummary(
    done: 0,
    partial: 0,
    missed: 0,
    skipped: 0,
    pending: 0,
    weightedCompletion: 0,
  );

  final int done;
  final int partial;
  final int missed;
  final int skipped;

  /// Unresolved — today and the future. Reported so the UI can say "so far",
  /// never folded into the score.
  final int pending;

  final double weightedCompletion;

  /// Occurrences that actually count: done + partial + missed. Skips, pauses,
  /// unscheduled days and anything still pending are all out.
  int get eligible => done + partial + missed;

  /// Weighted completion over eligible expectation.
  ///
  /// Null when nothing is eligible yet. A null score is not zero — a brand new
  /// commitment has no consistency, and rendering it as 0% would be a lie the
  /// user has no way to fix.
  double? get consistency =>
      eligible == 0 ? null : weightedCompletion / eligible;

  /// Whole-percent form for display, or null when there is nothing to score.
  int? get percent =>
      consistency == null ? null : (consistency! * 100).round();

  @override
  String toString() => 'Consistency(${percent ?? '—'}%, done=$done, '
      'partial=$partial, missed=$missed, skipped=$skipped, pending=$pending)';
}

/// Momentum: how long runs last and how fast they resume.
class StreakSummary {
  const StreakSummary({
    required this.current,
    required this.longest,
    required this.averageStreak,
    required this.averageRecoveryDays,
    required this.completedRuns,
  });

  static const StreakSummary empty = StreakSummary(
    current: 0,
    longest: 0,
    averageStreak: 0,
    averageRecoveryDays: null,
    completedRuns: 0,
  );

  final int current;
  final int longest;
  final double averageStreak;

  /// Mean length of the gaps between runs — the differentiating metric. Null
  /// until at least one gap has been closed by a return, because an ongoing
  /// lapse has no recovery time yet.
  final double? averageRecoveryDays;

  /// Runs that have ended. Used to gate insights that need real history.
  final int completedRuns;

  @override
  String toString() => 'Streaks(current=$current, longest=$longest, '
      'avg=$averageStreak, recovery=$averageRecoveryDays)';
}
