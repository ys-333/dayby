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

    /// Inclusive last paused day.
    required CivilDate to,
  }) = _PausePeriod;
}

extension PauseCoverage on PausePeriod {
  bool covers(CivilDate date) => date >= from && date <= to;
}
