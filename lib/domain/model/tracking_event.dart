import 'package:freezed_annotation/freezed_annotation.dart';

import '../time/civil_date.dart';

part 'tracking_event.freezed.dart';

/// What the user actually recorded. Distinct from a status: a status is derived,
/// an event is a fact the user asserted.
enum TrackingKind {
  /// A completion, worth [count] toward the target.
  done,

  /// Attempted but short of the target. Scored at partial credit.
  partial,

  /// Deliberately not doing it. Removed from the denominator entirely — this is
  /// the difference between "I chose not to" and "I failed to".
  skipped,
}

@freezed
abstract class TrackingEvent with _$TrackingEvent {
  const factory TrackingEvent({
    required String id,
    required String commitmentId,

    /// The accounting day this event counts toward — not the wall-clock date it
    /// was entered on. Backfilling sets this to a past date deliberately.
    required CivilDate accountingDate,
    required DateTime recordedAtUtc,
    required TrackingKind kind,
    @Default(1) int count,
    int? minutes,
    String? note,
  }) = _TrackingEvent;
}
