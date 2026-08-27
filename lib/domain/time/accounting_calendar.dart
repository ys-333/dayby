import 'package:timezone/timezone.dart' as tz;

import 'civil_date.dart';
import 'clock.dart';

/// Period granularities the accounting engine understands.
enum PeriodScope { daily, weekly, monthly }

/// Resolves instants to accounting days, and dates to the periods that contain
/// them. Every timezone and day-boundary decision in the app funnels through
/// here — nothing else should reason about either.
///
/// The accounting day is `[dayBoundaryHour, dayBoundaryHour)` in local wall
/// time, so with the default 04:00 boundary the Aug 27 accounting day runs from
/// Aug 27 04:00 to Aug 28 03:59 local. Late-night activity therefore lands on
/// the day it *felt* like, which is the whole point.
class AccountingCalendar {
  const AccountingCalendar({
    required this.zone,
    this.dayBoundaryHour = 4,
    this.weekStartsOn = DateTime.monday,
  });

  final tz.Location zone;
  final int dayBoundaryHour;
  final int weekStartsOn;

  /// Which accounting day an instant belongs to.
  ///
  /// Compares local *wall-clock* hour rather than subtracting a [Duration].
  /// That distinction matters across DST: on a spring-forward day an hour of
  /// wall time does not exist, so `local - 4h` and "before 04:00 local" are not
  /// the same question. The spec defines the boundary in wall time, so we read
  /// wall time.
  CivilDate accountingDateOf(DateTime instant) {
    final local = tz.TZDateTime.from(instant.toUtc(), zone);
    final date = CivilDate(local.year, local.month, local.day);
    return local.hour < dayBoundaryHour ? date.plusDays(-1) : date;
  }

  /// The accounting day in progress right now.
  CivilDate today(Clock clock) => accountingDateOf(clock.nowUtc());

  /// The instant an accounting day opens.
  DateTime startOfAccountingDay(CivilDate date) =>
      tz.TZDateTime(zone, date.year, date.month, date.day, dayBoundaryHour);

  /// Exclusive upper bound of an accounting day.
  DateTime endOfAccountingDay(CivilDate date) =>
      startOfAccountingDay(date.plusDays(1));

  /// True once the day has closed and its unchecked occurrences can become
  /// MISSED. Today is never closed; tomorrow is emphatically never closed.
  bool isDayClosed(CivilDate date, Clock clock) => date < today(clock);

  CivilDate startOfWeek(CivilDate d) => d.startOfWeek(weekStartsOn);
  CivilDate endOfWeek(CivilDate d) => startOfWeek(d).plusDays(6);

  /// The period of [scope] containing [date].
  CivilDateRange periodContaining(PeriodScope scope, CivilDate date) {
    switch (scope) {
      case PeriodScope.daily:
        return CivilDateRange(date, date);
      case PeriodScope.weekly:
        return CivilDateRange(startOfWeek(date), endOfWeek(date));
      case PeriodScope.monthly:
        return CivilDateRange(date.startOfMonth, date.endOfMonth);
    }
  }

  /// True once a period has fully elapsed, which is the only moment its target
  /// may be judged. An open period is never a failure, however far behind it is.
  bool isPeriodClosed(CivilDateRange period, Clock clock) =>
      period.end < today(clock);

  /// Every period of [scope] that overlaps [range], in order.
  List<CivilDateRange> periodsOverlapping(
    PeriodScope scope,
    CivilDateRange range,
  ) {
    final out = <CivilDateRange>[];
    var cursor = periodContaining(scope, range.start);
    while (cursor.start <= range.end) {
      out.add(cursor);
      cursor = periodContaining(scope, cursor.end.plusDays(1));
    }
    return out;
  }
}
