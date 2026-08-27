import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/accounting/accounting_engine.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/analytics/analytics_engine.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/recurrence/recurrence_engine.dart';
import 'package:riyaz/domain/seed/synthetic_seeder.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/domain/time/clock.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/dates.dart';
import '../../support/fixtures.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  const seeder = SyntheticSeeder();
  final endingOn = d(2026, 8, 27);

  SyntheticDataset generate({int seed = 42}) =>
      seeder.generate(endingOn: endingOn, seed: seed);

  group('determinism', () {
    test('the same seed reproduces the same dataset exactly', () {
      final a = generate();
      final b = generate();
      expect(a.events.length, b.events.length);
      expect(
        a.events.map((e) => '${e.id}:${e.accountingDate.iso}:${e.kind.name}'),
        b.events.map((e) => '${e.id}:${e.accountingDate.iso}:${e.kind.name}'),
      );
      expect(a.pauses.length, b.pauses.length);
    });

    test('a different seed produces different behaviour', () {
      expect(generate().events.length,
          isNot(generate(seed: 7).events.length));
    });
  });

  group('shape of the generated year', () {
    late SyntheticDataset data;
    setUp(() => data = generate());

    test('produces the requested commitments across a year', () {
      expect(data.commitments, hasLength(20));
      expect(data.events.length, greaterThan(1000));
      for (final e in data.events) {
        expect(e.accountingDate <= endingOn, isTrue);
        expect(e.accountingDate >= endingOn.plusDays(-364), isTrue);
      }
    });

    test('contains every event kind, so scoring paths are exercised', () {
      final kinds = data.events.map((e) => e.kind).toSet();
      expect(kinds, containsAll(TrackingKind.values));
    });

    test('contains pauses, schedule changes and archived commitments', () {
      expect(data.pauses, isNotEmpty);
      final versioned = data.schedules
          .where((s) => s.effectiveTo != null)
          .map((s) => s.commitmentId)
          .toSet();
      expect(versioned, isNotEmpty,
          reason: 'schedule-versioning code needs versioned data to meet');
      expect(
        data.commitments.where((c) => c.state == CommitmentState.archived),
        isNotEmpty,
      );
    });

    test('every schedule and event belongs to a real commitment', () {
      final ids = data.commitments.map((c) => c.id).toSet();
      expect(data.schedules.every((s) => ids.contains(s.commitmentId)), isTrue);
      expect(data.events.every((e) => ids.contains(e.commitmentId)), isTrue);
      expect(data.pauses.every((p) => ids.contains(p.commitmentId)), isTrue);
    });
  });

  group('end to end through the engines', () {
    test('a seeded year yields believable analytics', () {
      final data = generate();
      final calendar = calendarFor('Asia/Kolkata');
      final engine = AccountingEngine(
        calendar: calendar,
        recurrence: RecurrenceEngine(calendar),
      );
      const analytics = AnalyticsEngine();
      final clock = FixedClock.iso('2026-08-28T10:00:00+05:30');
      final year = CivilDateRange(endingOn.plusDays(-364), endingOn);

      final first = data.commitments.first;
      final resolved = engine.resolveRange(
        commitmentId: first.id,
        schedules:
            data.schedules.where((s) => s.commitmentId == first.id).toList(),
        pauses: data.pauses.where((p) => p.commitmentId == first.id).toList(),
        events: data.events.where((e) => e.commitmentId == first.id).toList(),
        range: year,
        clock: clock,
      );

      expect(resolved, isNotEmpty);

      final summary = analytics.summarize(resolved);
      expect(summary.consistency, isNotNull);
      expect(summary.consistency, inInclusiveRange(0.0, 1.0));
      expect(summary.eligible, greaterThan(30));

      // Momentum modelling should yield real runs and real recoveries, which a
      // per-day coin flip would not.
      final streaks = analytics.streaks(resolved);
      expect(streaks.longest, greaterThan(2));
      expect(streaks.completedRuns, greaterThan(2));
      expect(streaks.averageRecoveryDays, isNotNull);

      // Nothing in the past may still be pending.
      final stalePending = resolved.where((r) =>
          r.status == OccurrenceStatus.pending &&
          r.occurrence.span.end < calendar.today(clock));
      expect(stalePending, isEmpty);
    });

    test('a rolling trend over the year has no impossible values', () {
      final data = generate();
      final calendar = calendarFor('Asia/Kolkata');
      final engine = AccountingEngine(
        calendar: calendar,
        recurrence: RecurrenceEngine(calendar),
      );
      const analytics = AnalyticsEngine();
      final clock = FixedClock.iso('2026-08-28T10:00:00+05:30');
      final range = CivilDateRange(endingOn.plusDays(-89), endingOn);

      final c = data.commitments[1];
      final resolved = engine.resolveRange(
        commitmentId: c.id,
        schedules: data.schedules.where((s) => s.commitmentId == c.id).toList(),
        pauses: data.pauses.where((p) => p.commitmentId == c.id).toList(),
        events: data.events.where((e) => e.commitmentId == c.id).toList(),
        range: range,
        clock: clock,
      );

      final trend =
          analytics.rollingConsistency(resolved: resolved, range: range);
      expect(trend, hasLength(90));
      for (final point in trend) {
        if (point.consistency != null) {
          expect(point.consistency, inInclusiveRange(0.0, 1.0));
        }
      }
      expect(trend.any((p) => p.consistency != null), isTrue);
    });
  });
}
