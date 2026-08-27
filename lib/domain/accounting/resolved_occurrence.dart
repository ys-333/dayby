import '../analytics/scoring.dart';
import '../recurrence/expected_occurrence.dart';
import 'occurrence_status.dart';

/// An expected occurrence with the user's actual behaviour applied to it.
class ResolvedOccurrence {
  const ResolvedOccurrence({
    required this.occurrence,
    required this.status,
    required this.completed,
    required this.credit,
    this.note,
  });

  final ExpectedOccurrence occurrence;
  final OccurrenceStatus status;

  /// Completions recorded within the occurrence's span.
  final int completed;

  /// Weighted credit toward consistency. Zero for anything not [done] or
  /// [partial]; excluded statuses contribute neither credit nor denominator.
  final double credit;

  /// The most recent note recorded within this occurrence's span. Notes are
  /// optional context, never required, and never affect scoring.
  final String? note;

  int get target => occurrence.target;

  bool get isEligible => status.isEligible;

  /// Progress for display: "2 / 4 this week".
  String get progressLabel => '$completed / $target';

  @override
  String toString() =>
      'Resolved(${occurrence.runtimeType}, ${status.name}, '
      '$completed/$target, credit=$credit)';
}

/// Convenience for building a resolution with credit derived from status.
ResolvedOccurrence resolutionOf({
  required ExpectedOccurrence occurrence,
  required OccurrenceStatus status,
  required int completed,
  required ScoringWeights weights,
  String? note,
}) {
  final credit = switch (status) {
    OccurrenceStatus.done => weights.done,
    OccurrenceStatus.partial => occurrence is PeriodOccurrence
        ? weights.creditForPeriod(
            completed: completed,
            target: occurrence.target,
          )
        : weights.partial,
    _ => 0.0,
  };
  return ResolvedOccurrence(
    occurrence: occurrence,
    status: status,
    completed: completed,
    credit: credit,
    note: note,
  );
}
