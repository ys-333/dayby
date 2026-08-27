import 'package:freezed_annotation/freezed_annotation.dart';

import '../time/accounting_calendar.dart';

part 'frequency.freezed.dart';

/// How often a commitment is expected.
///
/// The split that matters is between *daily-shaped* frequencies, which produce
/// one expected occurrence per matching date, and *period-shaped* ones, which
/// produce a single target over a week or a month. A period-shaped frequency
/// must never be expanded into daily occurrences — that is what invents a
/// "missed Wednesday" for a 4x/week commitment.
@freezed
sealed class Frequency with _$Frequency {
  /// Every day.
  const factory Frequency.daily({@Default(1) int target}) = DailyFrequency;

  /// Specific weekdays, using [DateTime.monday]..[DateTime.sunday].
  const factory Frequency.weekdays({
    required Set<int> days,
    @Default(1) int target,
  }) = WeekdaysFrequency;

  /// Every n days, counted from the schedule's effectiveFrom.
  const factory Frequency.everyNDays({
    required int n,
    @Default(1) int target,
  }) = EveryNDaysFrequency;

  /// n times per week, in any distribution across the week.
  const factory Frequency.timesPerWeek({required int target}) =
      TimesPerWeekFrequency;

  /// n times per month, in any distribution across the month.
  const factory Frequency.timesPerMonth({required int target}) =
      TimesPerMonthFrequency;
}

extension FrequencyShape on Frequency {
  /// The granularity this frequency is accounted at.
  PeriodScope get scope => switch (this) {
        DailyFrequency() ||
        WeekdaysFrequency() ||
        EveryNDaysFrequency() =>
          PeriodScope.daily,
        TimesPerWeekFrequency() => PeriodScope.weekly,
        TimesPerMonthFrequency() => PeriodScope.monthly,
      };

  /// True when this frequency is scored over a period rather than per day.
  bool get isPeriodScoped => scope != PeriodScope.daily;

  /// Expected completions per occurrence (per day, or per period).
  int get target => switch (this) {
        DailyFrequency(:final target) => target,
        WeekdaysFrequency(:final target) => target,
        EveryNDaysFrequency(:final target) => target,
        TimesPerWeekFrequency(:final target) => target,
        TimesPerMonthFrequency(:final target) => target,
      };
}
