import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/data/repository/review_repository.dart';
import 'package:riyaz/domain/analytics/consistency_summary.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/time/accounting_calendar.dart';
import 'package:riyaz/domain/time/civil_date.dart';

part 'week_review_controller.g.dart';

/// How far back recovery time is measured for the review.
///
/// Wider than the week being reviewed, and deliberately. A single week rarely
/// contains a whole lapse-and-return, so "average recovery" computed inside it
/// would usually be null and occasionally be one unrepresentative number. It
/// is a long-run trait, and the review reports it as one.
const int _recoveryWindowDays = 90;

/// One commitment's week.
class CommitmentWeek {
  const CommitmentWeek({required this.commitment, required this.summary});

  final Commitment commitment;
  final ConsistencySummary summary;
}

/// What the user sees when a week ends.
class WeekReview {
  const WeekReview({
    required this.week,
    required this.summary,
    required this.best,
    required this.hardest,
    required this.averageRecoveryDays,
    required this.scored,
  });

  final CivilDateRange week;

  /// Every commitment's occurrences for the week, together.
  final ConsistencySummary summary;

  /// The week's strongest and weakest commitments, or null when naming one
  /// would be arbitrary. See [namesAreMeaningful].
  final CommitmentWeek? best;
  final CommitmentWeek? hardest;

  /// Long-run recovery, over [_recoveryWindowDays]. Null until at least one
  /// lapse has actually been recovered from — an ongoing one has no duration
  /// yet, and reporting zero would claim a resilience never demonstrated.
  final double? averageRecoveryDays;

  /// Commitments with at least one eligible occurrence this week.
  final int scored;

  /// Whether the week is worth showing at all.
  ///
  /// A week in which nothing was expected — a new install, a holiday with
  /// everything paused — has no result to report, and a review that opens with
  /// "0%" over an empty denominator is worse than no review.
  bool get hasResult => summary.eligible > 0;

  /// Whether naming a best and a hardest says anything.
  ///
  /// Two conditions, and the second is the one that matters. With a single
  /// commitment, "best" and "hardest" are the same row and the pair is
  /// nonsense. With several that all scored identically, picking one to call
  /// hardest is the app inventing a judgement out of a tie — which is exactly
  /// what "describe behaviour, don't judge the user" forbids.
  bool get namesAreMeaningful =>
      scored >= 2 &&
      best != null &&
      hardest != null &&
      best!.summary.percent != hardest!.summary.percent;
}

/// The most recent week that is **over**.
///
/// The week in progress is deliberately not reviewable. A period's result is
/// final only at period close — that is the accounting rule the whole model
/// rests on — so offering a verdict on Wednesday would contradict every other
/// screen in the app.
@riverpod
CivilDateRange lastClosedWeek(Ref ref) {
  final calendar = ref.watch(accountingCalendarProvider);
  final current = calendar.periodContaining(
    PeriodScope.weekly,
    ref.watch(todayProvider),
  );
  return CivilDateRange(
    current.start.plusDays(-7),
    current.start.plusDays(-1),
  );
}

@riverpod
ReviewRepository reviewRepository(Ref ref) =>
    ReviewRepository(ref.watch(appDatabaseProvider));

/// Whether a closed week is waiting to be read.
///
/// False once dismissed, and false for a week with nothing in it, so the card
/// cannot greet a new user with a verdict on a week before they installed the
/// app.
@riverpod
Stream<bool> reviewPending(Ref ref) async* {
  final week = ref.watch(lastClosedWeekProvider);
  final review = await ref.watch(weekReviewProvider(week.start).future);
  if (!review.hasResult) {
    yield false;
    return;
  }
  yield* ref
      .watch(reviewRepositoryProvider)
      .watchLastSeenWeek()
      .map((seen) => seen == null || seen < week.start);
}

/// The review for the week beginning [weekStart].
@riverpod
Stream<WeekReview> weekReview(Ref ref, CivilDate weekStart) {
  final analytics = ref.watch(analyticsEngineProvider);
  final week = CivilDateRange(weekStart, weekStart.plusDays(6));

  // One read, wide enough for both jobs: the week itself is sliced out of it
  // for the counts, and the whole window feeds recovery.
  final range = CivilDateRange(
    week.end.plusDays(-(_recoveryWindowDays - 1)),
    week.end,
  );

  return ref.watch(resolutionServiceProvider).watch(range).map((history) {
    final inWeek = [
      for (final r in history.all)
        if (week.contains(r.occurrence.span.end)) r,
    ];

    final scored = <CommitmentWeek>[];
    for (final commitment in history.commitments) {
      final resolved = [
        for (final r in history.forCommitment(commitment.id))
          if (week.contains(r.occurrence.span.end)) r,
      ];
      final summary = analytics.summarize(resolved);
      // Only commitments the week actually asked something of. A paused or
      // not-yet-started one has no score, and ranking it against those that do
      // would put a commitment nobody was tracking at the bottom of the list.
      if (summary.eligible == 0) continue;
      scored.add(CommitmentWeek(commitment: commitment, summary: summary));
    }

    scored.sort((a, b) {
      final byScore =
          (b.summary.consistency ?? 0).compareTo(a.summary.consistency ?? 0);
      // Ties broken by name so the same week always reads the same way. A
      // review that reshuffles between openings looks like the numbers moved.
      return byScore != 0
          ? byScore
          : a.commitment.name.compareTo(b.commitment.name);
    });

    return WeekReview(
      week: week,
      summary: analytics.summarize(inWeek),
      best: scored.isEmpty ? null : scored.first,
      hardest: scored.isEmpty ? null : scored.last,
      averageRecoveryDays: analytics.streaks(history.all).averageRecoveryDays,
      scored: scored.length,
    );
  });
}

/// Dismissing the review.
@riverpod
ReviewActions reviewActions(Ref ref) => ReviewActions(
      repository: ref.watch(reviewRepositoryProvider),
      week: ref.watch(lastClosedWeekProvider),
    );

class ReviewActions {
  const ReviewActions({required this.repository, required this.week});

  final ReviewRepository repository;
  final CivilDateRange week;

  /// Marks the closed week read. Deliberately not undoable: nothing was
  /// written to history, and the review is reachable again from History for as
  /// long as the data exists.
  Future<void> dismiss() => repository.markSeen(week.start);
}
