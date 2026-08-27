import 'consistency_summary.dart';

/// How a calendar cell should read.
///
/// Bands, not raw percentages, because a calendar is scanned rather than read:
/// the eye needs three or four distinguishable states, not a hundred.
enum DayBand {
  /// At or above [DayBands.strongThreshold].
  strong,

  /// Between the two thresholds — real effort, short of the mark.
  partial,

  /// Below [DayBands.weakThreshold].
  weak,

  /// Nothing was expected, or everything expected was skipped or paused.
  /// Distinct from [weak]: an empty day is not a bad day.
  none,

  /// Not yet lived. Must never render as failure.
  future,
}

/// Thresholds in one place so the calendar, the year grid and any future
/// heatmap agree about what "a good day" means.
class DayBands {
  const DayBands({
    this.strongThreshold = 0.8,
    this.weakThreshold = 0.4,
  });

  static const DayBands standard = DayBands();

  final double strongThreshold;
  final double weakThreshold;

  /// Bands a day's summary.
  ///
  /// [isFuture] wins over everything. A future day has no behaviour to judge,
  /// and colouring it as a miss is the single most common way a habit tracker
  /// turns into a guilt machine.
  DayBand bandFor(ConsistencySummary summary, {required bool isFuture}) {
    if (isFuture) return DayBand.future;
    final consistency = summary.consistency;
    if (consistency == null) return DayBand.none;
    if (consistency >= strongThreshold) return DayBand.strong;
    if (consistency >= weakThreshold) return DayBand.partial;
    return DayBand.weak;
  }
}
