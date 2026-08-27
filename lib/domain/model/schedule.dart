import 'package:freezed_annotation/freezed_annotation.dart';

import '../time/civil_date.dart';
import 'frequency.dart';

part 'schedule.freezed.dart';

/// An effective-dated schedule version.
///
/// Schedules are never mutated in a way that changes history. Changing a
/// commitment's frequency closes the current version and opens a new one, so a
/// past date is always evaluated against the schedule that was in force then.
@freezed
abstract class CommitmentSchedule with _$CommitmentSchedule {
  const factory CommitmentSchedule({
    required String id,
    required String commitmentId,
    required CivilDate effectiveFrom,

    /// Inclusive last day this version applies. Null means open-ended.
    CivilDate? effectiveTo,
    required Frequency frequency,

    /// Target minutes per occurrence, for duration-based commitments.
    int? targetMinutes,
  }) = _CommitmentSchedule;
}

extension ScheduleValidity on CommitmentSchedule {
  bool coversDate(CivilDate date) =>
      date >= effectiveFrom && (effectiveTo == null || date <= effectiveTo!);
}
