import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/time/civil_date.dart';

import '../../support/dates.dart';

void main() {
  group('day arithmetic', () {
    test('crosses month boundaries', () {
      expect(d(2026, 8, 31).plusDays(1), d(2026, 9, 1));
      expect(d(2026, 9, 1).plusDays(-1), d(2026, 8, 31));
    });

    test('crosses year boundaries', () {
      expect(d(2026, 12, 31).plusDays(1), d(2027, 1, 1));
      expect(d(2027, 1, 1).plusDays(-1), d(2026, 12, 31));
    });

    test('handles leap and non-leap Februaries', () {
      // 2028 is a leap year; 2026 is not.
      expect(d(2028, 2, 28).plusDays(1), d(2028, 2, 29));
      expect(d(2028, 2, 29).plusDays(1), d(2028, 3, 1));
      expect(d(2026, 2, 28).plusDays(1), d(2026, 3, 1));
      expect(d(2028, 2, 1).endOfMonth, d(2028, 2, 29));
      expect(d(2026, 2, 1).endOfMonth, d(2026, 2, 28));
    });

    test('century leap rules', () {
      // 2000 was a leap year, 1900 was not.
      expect(d(2000, 2, 1).endOfMonth, d(2000, 2, 29));
      expect(d(1900, 2, 1).endOfMonth, d(1900, 2, 28));
    });

    test('epoch day round-trips', () {
      for (final date in [d(1970, 1, 1), d(2026, 8, 28), d(2100, 12, 31)]) {
        expect(CivilDate.fromEpochDay(date.epochDay), date);
      }
      expect(d(1970, 1, 1).epochDay, 0);
    });
  });

  group('week and month bounds', () {
    test('startOfWeek respects the configured first day', () {
      // 2026-08-28 is a Friday.
      expect(d(2026, 8, 28).weekday, DateTime.friday);
      expect(d(2026, 8, 28).startOfWeek(DateTime.monday), d(2026, 8, 24));
      expect(d(2026, 8, 28).startOfWeek(DateTime.sunday), d(2026, 8, 23));
    });

    test('a date that is already the week start stays put', () {
      expect(d(2026, 8, 24).startOfWeek(DateTime.monday), d(2026, 8, 24));
    });

    test('month bounds', () {
      expect(d(2026, 8, 17).startOfMonth, d(2026, 8, 1));
      expect(d(2026, 8, 17).endOfMonth, d(2026, 8, 31));
      expect(d(2026, 12, 5).endOfMonth, d(2026, 12, 31));
    });
  });

  group('parsing, ordering and ranges', () {
    test('iso round-trip', () {
      expect(CivilDate.parse('2026-08-28'), d(2026, 8, 28));
      expect(d(2026, 8, 28).iso, '2026-08-28');
      expect(d(999, 1, 2).iso, '0999-01-02');
      expect(() => CivilDate.parse('2026-8-28'), throwsFormatException);
    });

    test('comparison operators', () {
      expect(d(2026, 8, 27) < d(2026, 8, 28), isTrue);
      expect(d(2026, 8, 28) < d(2026, 8, 28), isFalse);
      expect(d(2026, 8, 28) <= d(2026, 8, 28), isTrue);
      expect(d(2026, 9, 1) > d(2026, 8, 31), isTrue);
      expect(d(2026, 8, 28) == d(2026, 8, 28), isTrue);
    });

    test('range enumerates inclusively', () {
      final r = CivilDateRange(d(2026, 8, 24), d(2026, 8, 30));
      expect(r.lengthInDays, 7);
      expect(r.dates.length, 7);
      expect(r.dates.first, d(2026, 8, 24));
      expect(r.dates.last, d(2026, 8, 30));
      expect(r.contains(d(2026, 8, 24)), isTrue);
      expect(r.contains(d(2026, 8, 30)), isTrue);
      expect(r.contains(d(2026, 8, 31)), isFalse);
    });
  });
}
