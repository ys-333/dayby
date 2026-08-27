/// The resolved state of an expected occurrence.
///
/// Only [done], [partial] and [missed] participate in a consistency
/// denominator. The rest are excluded, each for a different reason, and
/// conflating any two of them corrupts every number downstream.
enum OccurrenceStatus {
  /// Not yet resolved: the day or period has not closed. Covers today *and*
  /// every future date — both are excluded from the denominator, because a
  /// consistency score may never be dragged down by time that has not passed.
  pending,

  /// Target met.
  done,

  /// Attempted, short of target, and the window has closed.
  partial,

  /// Expected, not done, window closed. The only status that counts as zero
  /// while staying in the denominator.
  missed,

  /// Deliberately skipped. Leaves the denominator entirely — "I chose not to"
  /// is not a failure. Surfaced separately in the UI so it stays visible.
  skipped,

  /// Commitment was paused. Excluded.
  paused,

  /// Schedule did not expect anything. Excluded.
  notScheduled,
}

extension OccurrenceStatusScoring on OccurrenceStatus {
  /// Whether this status belongs in a consistency denominator at all.
  bool get isEligible => switch (this) {
        OccurrenceStatus.done ||
        OccurrenceStatus.partial ||
        OccurrenceStatus.missed =>
          true,
        OccurrenceStatus.pending ||
        OccurrenceStatus.skipped ||
        OccurrenceStatus.paused ||
        OccurrenceStatus.notScheduled =>
          false,
      };
}
