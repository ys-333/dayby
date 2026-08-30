import 'package:freezed_annotation/freezed_annotation.dart';

import '../time/civil_date.dart';

part 'pause_period.freezed.dart';

/// A stretch of days a commitment is suspended for. Paused days leave the
/// denominator entirely; they are not misses.
@freezed
abstract class PausePeriod with _$PausePeriod {
  const factory PausePeriod({
    required String id,
    required String commitmentId,
    required CivilDate from,

    /// Inclusive last paused day, or **null while the pause is still open**.
    ///
    /// Null rather than a far-future sentinel. "Pause until I resume" is the
    /// common case — an injury, a trip of unknown length — and a date like
    /// 9999-12-31 standing in for "unknown" leaks everywhere it is touched:
    /// into [covers], into any calendar arithmetic over the span, into the
    /// year grid's ranges, and into the backup file, which `backup_codec.dart`
    /// keeps human-readable precisely so a damaged one can be repaired by
    /// hand. A reader finding `"to": "9999-12-31"` has to know the convention;
    /// a reader finding `"to": null` does not.
    CivilDate? to,
  }) = _PausePeriod;
}

extension PauseCoverage on PausePeriod {
  /// Whether [date] falls inside the pause.
  ///
  /// An open pause covers every day from [from] onward, the future included —
  /// which is correct: it means the recurrence engine expects nothing on those
  /// days, so they can never accrue a miss while the pause stands.
  bool covers(CivilDate date) {
    final end = to;
    return date >= from && (end == null || date <= end);
  }

  /// Still running, with no end recorded.
  bool get isOpen => to == null;

  /// True for a pause that covers no day at all.
  ///
  /// Reachable only transiently — pausing and resuming on the same day would
  /// close a pause at the day before it began. Callers delete these rather
  /// than store a row whose end precedes its start, for the same reason
  /// `updateCommitment` amends rather than closing a schedule at `on - 1`.
  bool get isEmpty {
    final end = to;
    return end != null && end < from;
  }
}
