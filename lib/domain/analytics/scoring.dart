/// How completion converts to credit. Centralised so it can change in one
/// place — screens must never inline a weight.
class ScoringWeights {
  const ScoringWeights({this.done = 1.0, this.partial = 0.5});

  static const ScoringWeights standard = ScoringWeights();

  /// Credit for meeting the target.
  final double done;

  /// Credit for a closed daily occurrence that fell short.
  ///
  /// Flat rather than proportional, per the spec: a daily commitment that was
  /// attempted counts as half, regardless of how far short it landed. Period
  /// occurrences are scored proportionally instead — see
  /// [creditForPeriod] — because a 3-of-4 week is meaningfully better than a
  /// 1-of-4 week and the spec reports it as 75%.
  final double partial;

  /// Credit for a closed period occurrence: its actual completion ratio,
  /// capped at full credit so overshooting a target cannot inflate a score.
  double creditForPeriod({required int completed, required int target}) {
    if (target <= 0) return 0;
    final ratio = completed / target;
    return ratio > done ? done : ratio;
  }
}
