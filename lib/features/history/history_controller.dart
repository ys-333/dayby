import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/domain/analytics/consistency_summary.dart';
import 'package:riyaz/domain/analytics/day_band.dart';
import 'package:riyaz/domain/time/civil_date.dart';

part 'history_controller.g.dart';

/// One cell in the month grid.
class CalendarDay {
  const CalendarDay({
    required this.date,
    required this.band,
    required this.summary,
    required this.inMonth,
  });

  final CivilDate date;
  final DayBand band;
  final ConsistencySummary summary;

  /// False for the leading and trailing days that pad the grid to whole weeks.
  final bool inMonth;
}

class CalendarMonth {
  const CalendarMonth({
    required this.month,
    required this.days,
    required this.summary,
  });

  /// First day of the month being shown.
  final CivilDate month;

  /// Whole weeks covering the month, so the grid is always a clean 7xN.
  final List<CalendarDay> days;

  /// Totals for the month itself, excluding the padding days.
  final ConsistencySummary summary;
}

/// The month the history screen is showing.
@riverpod
class VisibleMonth extends _$VisibleMonth {
  @override
  CivilDate build() => ref.watch(todayProvider).startOfMonth;

  void previous() =>
      state = state.plusDays(-1).startOfMonth;

  void next() {
    final limit = ref.read(todayProvider).startOfMonth;
    final candidate = state.endOfMonth.plusDays(1).startOfMonth;
    // Never page past the current month: there is nothing there to show, and
    // an empty future grid reads as data the user is missing.
    state = candidate > limit ? limit : candidate;
  }

  bool get isAtLatest => state >= ref.read(todayProvider).startOfMonth;
}

@riverpod
Stream<CalendarMonth> calendarMonth(Ref ref, CivilDate month) {
  final calendar = ref.watch(accountingCalendarProvider);
  final analytics = ref.watch(analyticsEngineProvider);
  final today = ref.watch(todayProvider);

  final gridStart = calendar.startOfWeek(month.startOfMonth);
  final gridEnd = calendar.endOfWeek(month.endOfMonth);
  final range = CivilDateRange(gridStart, gridEnd);

  return ref.watch(resolutionServiceProvider).watch(range).map((history) {
    final byDay = analytics.bucketed(
      resolved: history.all,
      bucketOf: (date) => date,
    );

    const bands = DayBands.standard;
    final days = [
      for (final date in range.dates)
        CalendarDay(
          date: date,
          summary: byDay[date] ?? ConsistencySummary.empty,
          band: bands.bandFor(
            byDay[date] ?? ConsistencySummary.empty,
            isFuture: date > today,
          ),
          inMonth: date.month == month.month && date.year == month.year,
        ),
    ];

    final monthOnly = [
      for (final r in history.all)
        if (r.occurrence.span.end.month == month.month &&
            r.occurrence.span.end.year == month.year)
          r,
    ];

    return CalendarMonth(
      month: month.startOfMonth,
      days: days,
      summary: analytics.summarize(monthOnly),
    );
  });
}
