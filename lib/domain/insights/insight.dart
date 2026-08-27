/// What an insight is about, so the UI can group and ice-pick them.
enum InsightKind {
  /// How long runs typically last before they end.
  momentum,

  /// How fast the user returns after a lapse.
  recovery,

  /// Weekday patterns.
  dayOfWeek,

  /// Direction of travel over recent months.
  trend,

  /// Too many active daily commitments.
  load,
}

/// A single observation, already phrased for display.
///
/// Phrased descriptively, never as a verdict. "You tend to lose momentum after
/// six days" is information; "you failed to maintain your streak" is a
/// judgement, and a tracker that judges gets deleted.
class Insight {
  const Insight({
    required this.kind,
    required this.headline,
    this.detail,
  });

  final InsightKind kind;
  final String headline;
  final String? detail;

  @override
  String toString() => '$headline${detail == null ? '' : ' — $detail'}';
}

/// Either a set of observations, or an honest statement that there is not yet
/// enough history to make any.
class InsightsResult {
  const InsightsResult({
    required this.insights,
    required this.hasEnoughData,
    required this.eligibleObservations,
    required this.requiredObservations,
  });

  final List<Insight> insights;

  /// False until the thresholds are met. The UI shows an explanation rather
  /// than an empty list, because "no patterns" and "not enough data to look"
  /// mean completely different things to the reader.
  final bool hasEnoughData;

  final int eligibleObservations;
  final int requiredObservations;
}
