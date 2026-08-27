import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/analytics/consistency_summary.dart';
import 'package:riyaz/domain/analytics/day_band.dart';

ConsistencySummary summary({
  int done = 0,
  int partial = 0,
  int missed = 0,
  int skipped = 0,
  int pending = 0,
}) =>
    ConsistencySummary(
      done: done,
      partial: partial,
      missed: missed,
      skipped: skipped,
      pending: pending,
      weightedCompletion: done + partial * 0.5,
    );

void main() {
  const bands = DayBands.standard;

  test('a future day is never judged, whatever it contains', () {
    expect(
      bands.bandFor(summary(missed: 5), isFuture: true),
      DayBand.future,
    );
    expect(
      bands.bandFor(summary(done: 5), isFuture: true),
      DayBand.future,
    );
  });

  test('bands split at 80 and 40 percent', () {
    // 4/5 = 80% exactly -> strong (inclusive).
    expect(
      bands.bandFor(summary(done: 4, missed: 1), isFuture: false),
      DayBand.strong,
    );
    // 3/5 = 60% -> partial.
    expect(
      bands.bandFor(summary(done: 3, missed: 2), isFuture: false),
      DayBand.partial,
    );
    // 2/5 = 40% exactly -> partial (inclusive lower bound).
    expect(
      bands.bandFor(summary(done: 2, missed: 3), isFuture: false),
      DayBand.partial,
    );
    // 1/5 = 20% -> weak.
    expect(
      bands.bandFor(summary(done: 1, missed: 4), isFuture: false),
      DayBand.weak,
    );
  });

  test('a day with nothing eligible is none, not weak', () {
    expect(bands.bandFor(summary(), isFuture: false), DayBand.none);
    expect(
      bands.bandFor(summary(skipped: 3), isFuture: false),
      DayBand.none,
      reason: 'a fully skipped day is not a failed day',
    );
    expect(
      bands.bandFor(summary(pending: 2), isFuture: false),
      DayBand.none,
    );
  });

  test('an entirely missed day is weak, not none', () {
    expect(bands.bandFor(summary(missed: 3), isFuture: false), DayBand.weak);
  });

  test('thresholds are configurable', () {
    const strict = DayBands(strongThreshold: 0.95, weakThreshold: 0.6);
    expect(
      strict.bandFor(summary(done: 4, missed: 1), isFuture: false),
      DayBand.partial,
    );
  });
}
