import '../time/accounting_calendar.dart';
import '../time/civil_date.dart';

/// A unit of behaviour the schedule expected.
///
/// Two shapes, deliberately not collapsed into one. A daily commitment expects
/// something on a specific date. A period commitment expects a count across a
/// span and is indifferent to which days inside it are used.
sealed class ExpectedOccurrence {
  const ExpectedOccurrence({
    required this.commitmentId,
    required this.target,
  });

  final String commitmentId;
  final int target;

  /// The span this occurrence is judged over.
  CivilDateRange get span;

  PeriodScope get scope;
}

/// One expected day.
class DailyOccurrence extends ExpectedOccurrence {
  const DailyOccurrence({
    required super.commitmentId,
    required this.date,
    required super.target,
  });

  final CivilDate date;

  @override
  CivilDateRange get span => CivilDateRange(date, date);

  @override
  PeriodScope get scope => PeriodScope.daily;

  @override
  String toString() => 'Daily($commitmentId, ${date.iso}, target=$target)';
}

/// A target spread across a week or a month.
class PeriodOccurrence extends ExpectedOccurrence {
  PeriodOccurrence({
    required super.commitmentId,
    required this.scope,
    required this.period,
    required super.target,
    CivilDateRange? effective,
  }) : effective = effective ?? period;

  @override
  final PeriodScope scope;

  /// The calendar period, for display: "2 / 4 this week".
  final CivilDateRange period;

  /// The days actually judged. Equal to [period] except where a schedule
  /// version starts or ends mid-period, in which case it is clipped to the days
  /// that version governs.
  final CivilDateRange effective;

  /// True when a schedule boundary cut this period short, so [target] has been
  /// prorated down from the schedule's nominal target.
  bool get isClipped => effective != period;

  @override
  CivilDateRange get span => effective;

  @override
  String toString() => 'Period($commitmentId, ${scope.name}, $period'
      '${isClipped ? ' clipped=$effective' : ''}, target=$target)';
}
