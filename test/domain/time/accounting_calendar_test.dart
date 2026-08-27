import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/time/accounting_calendar.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/domain/time/clock.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../support/dates.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late AccountingCalendar kolkata;
  late AccountingCalendar newYork;

  setUp(() {
    kolkata = AccountingCalendar(zone: tz.getLocation('Asia/Kolkata'));
    newYork = AccountingCalendar(zone: tz.getLocation('America/New_York'));
  });

  group('4 AM boundary', () {
    test('late-night activity belongs to the day it felt like', () {
      // The spec's own example: both instants are the Aug 27 accounting day.
      expect(
        kolkata.accountingDateOf(DateTime.parse('2026-08-27T23:45:00+05:30')),
        d(2026, 8, 27),
      );
      expect(
        kolkata.accountingDateOf(DateTime.parse('2026-08-28T01:30:00+05:30')),
        d(2026, 8, 27),
      );
    });

    test('boundary is inclusive at open, exclusive at close', () {
      expect(
        kolkata.accountingDateOf(DateTime.parse('2026-08-28T03:59:59+05:30')),
        d(2026, 8, 27),
      );
      expect(
        kolkata.accountingDateOf(DateTime.parse('2026-08-28T04:00:00+05:30')),
        d(2026, 8, 28),
      );
    });

    test('midnight belongs to the previous accounting day', () {
      expect(
        kolkata.accountingDateOf(DateTime.parse('2026-08-28T00:00:00+05:30')),
        d(2026, 8, 27),
      );
    });

    test('boundary hour is configurable, including plain midnight', () {
      final midnight = AccountingCalendar(
        zone: tz.getLocation('Asia/Kolkata'),
        dayBoundaryHour: 0,
      );
      expect(
        midnight.accountingDateOf(DateTime.parse('2026-08-28T01:30:00+05:30')),
        d(2026, 8, 28),
      );
    });

    test('resolves via the zone, not the instant offset', () {
      // 22:30 UTC on Aug 27 is 04:00 Aug 28 in Kolkata — a new accounting day
      // there, but still Aug 27 (18:30) in New York.
      final instant = DateTime.parse('2026-08-27T22:30:00Z');
      expect(kolkata.accountingDateOf(instant), d(2026, 8, 28));
      expect(newYork.accountingDateOf(instant), d(2026, 8, 27));
    });
  });

  group('DST', () {
    // America/New_York 2026: forward Mar 8 (02:00 -> 03:00),
    // back Nov 1 (02:00 -> 01:00).
    test('the accounting day holding the skipped hour is 23 hours long', () {
      final start = newYork.startOfAccountingDay(d(2026, 3, 8));
      final end = newYork.endOfAccountingDay(d(2026, 3, 8));
      expect(end.difference(start), const Duration(hours: 24));

      // The short day is the one containing the skipped hour: Mar 7 04:00 EST
      // through Mar 8 03:59 EDT.
      final prev = newYork.startOfAccountingDay(d(2026, 3, 7));
      expect(start.difference(prev), const Duration(hours: 23));
    });

    test('fall-back day is 25 hours long', () {
      final start = newYork.startOfAccountingDay(d(2026, 10, 31));
      final next = newYork.startOfAccountingDay(d(2026, 11, 1));
      expect(next.difference(start), const Duration(hours: 25));
    });

    test('the repeated wall-clock hour resolves to one accounting day', () {
      // 01:30 local happens twice on Nov 1 (EDT then EST). Both are before the
      // 04:00 boundary, so both belong to Oct 31.
      final firstPass = DateTime.parse('2026-11-01T01:30:00-04:00');
      final secondPass = DateTime.parse('2026-11-01T01:30:00-05:00');
      expect(firstPass.isBefore(secondPass), isTrue);
      expect(newYork.accountingDateOf(firstPass), d(2026, 10, 31));
      expect(newYork.accountingDateOf(secondPass), d(2026, 10, 31));
    });

    test('the skipped wall-clock hour has no instants assigned to it', () {
      // 03:30 EDT exists on the forward day and is before the boundary.
      expect(
        newYork.accountingDateOf(DateTime.parse('2026-03-08T03:30:00-04:00')),
        d(2026, 3, 7),
      );
      expect(
        newYork.accountingDateOf(DateTime.parse('2026-03-08T04:00:00-04:00')),
        d(2026, 3, 8),
      );
    });
  });

  group('day and period closure', () {
    test('today is never closed and tomorrow certainly is not', () {
      final clock = FixedClock.iso('2026-08-28T10:00:00+05:30');
      expect(kolkata.today(clock), d(2026, 8, 28));
      expect(kolkata.isDayClosed(d(2026, 8, 28), clock), isFalse);
      expect(kolkata.isDayClosed(d(2026, 8, 29), clock), isFalse);
      expect(kolkata.isDayClosed(d(2026, 8, 27), clock), isTrue);
    });

    test('at 01:30 the accounting day is still yesterday, still open', () {
      final clock = FixedClock.iso('2026-08-28T01:30:00+05:30');
      expect(kolkata.today(clock), d(2026, 8, 27));
      expect(kolkata.isDayClosed(d(2026, 8, 27), clock), isFalse);
    });

    test('an open period is not closed however far behind it is', () {
      final clock = FixedClock.iso('2026-08-28T10:00:00+05:30');
      final thisWeek = kolkata.periodContaining(
        PeriodScope.weekly,
        d(2026, 8, 28),
      );
      expect(thisWeek, CivilDateRange(d(2026, 8, 24), d(2026, 8, 30)));
      expect(kolkata.isPeriodClosed(thisWeek, clock), isFalse);

      final lastWeek = kolkata.periodContaining(
        PeriodScope.weekly,
        d(2026, 8, 20),
      );
      expect(kolkata.isPeriodClosed(lastWeek, clock), isTrue);
    });

    test('monthly period closes only after the month ends', () {
      final august = kolkata.periodContaining(
        PeriodScope.monthly,
        d(2026, 8, 10),
      );
      expect(august, CivilDateRange(d(2026, 8, 1), d(2026, 8, 31)));
      expect(
        kolkata.isPeriodClosed(august, FixedClock.iso('2026-08-31T23:00+05:30')),
        isFalse,
      );
      expect(
        kolkata.isPeriodClosed(august, FixedClock.iso('2026-09-02T10:00+05:30')),
        isTrue,
      );
    });
  });

  group('periodsOverlapping', () {
    test('enumerates whole weeks covering a partial range', () {
      final weeks = kolkata.periodsOverlapping(
        PeriodScope.weekly,
        CivilDateRange(d(2026, 8, 26), d(2026, 9, 3)),
      );
      expect(weeks, [
        CivilDateRange(d(2026, 8, 24), d(2026, 8, 30)),
        CivilDateRange(d(2026, 8, 31), d(2026, 9, 6)),
      ]);
    });

    test('enumerates months across a year boundary', () {
      final months = kolkata.periodsOverlapping(
        PeriodScope.monthly,
        CivilDateRange(d(2026, 12, 15), d(2027, 1, 2)),
      );
      expect(months, [
        CivilDateRange(d(2026, 12, 1), d(2026, 12, 31)),
        CivilDateRange(d(2027, 1, 1), d(2027, 1, 31)),
      ]);
    });

    test('a single day yields exactly one period', () {
      final one = kolkata.periodsOverlapping(
        PeriodScope.weekly,
        CivilDateRange(d(2026, 8, 26), d(2026, 8, 26)),
      );
      expect(one, hasLength(1));
    });
  });
}
