import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/accounting/accounting_engine.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/accounting/resolved_occurrence.dart';
import 'package:riyaz/domain/analytics/analytics_engine.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/schedule.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/domain/recurrence/recurrence_engine.dart';
import 'package:riyaz/domain/time/clock.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/dates.dart';
import '../../support/fixtures.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late AccountingEngine engine;
  const analytics = AnalyticsEngine();
  final now = FixedClock.iso('2026-08-28T10:00:00+05:30');
  final august = CivilDateRange(d(2026, 8, 1), d(2026, 8, 27));

  setUp(() {
    final calendar = calendarFor('Asia/Kolkata');
    engine = AccountingEngine(
      calendar: calendar,
      recurrence: RecurrenceEngine(calendar),
    );
  });

  List<ResolvedOccurrence> resolve(
    List<TrackingEvent> events, {
    List<CommitmentSchedule>? schedules,
    CivilDateRange? range,
  }) =>
      engine.resolveRange(
        commitmentId: commitmentId,
        schedules: schedules ??
            [schedule(frequency: const Frequency.daily(), from: d(2026, 8, 1))],
        pauses: const [],
        events: events,
        range: range ?? august,
        clock: now,
      );

  group('backfill', () {
    test('recording a past day flips it out of missed', () {
      final before = resolve(const []);
      expect(before.first.status, OccurrenceStatus.missed);

      final after = resolve([event(d(2026, 8, 1))]);
      expect(after.first.status, OccurrenceStatus.done);
    });

    test('backfilling raises the period consistency it belongs to', () {
      final events = [
        for (final day in [1, 2, 3, 5, 6])
          event(d(2026, 8, day), id: 'e$day'),
      ];
      final before = analytics.summarize(resolve(events));

      final after = analytics.summarize(
        resolve([...events, event(d(2026, 8, 4), id: 'backfill')]),
      );

      expect(after.done, before.done + 1);
      expect(after.missed, before.missed - 1);
      expect(after.eligible, before.eligible);
      expect(after.consistency!, greaterThan(before.consistency!));
    });

    test('a backfilled day repairs the streak that spanned it', () {
      final broken = [
        for (final day in [1, 2, 3, 5, 6, 7])
          event(d(2026, 8, day), id: 'e$day'),
      ];
      expect(analytics.streaks(resolve(broken)).longest, 3);

      final repaired = [...broken, event(d(2026, 8, 4), id: 'backfill')];
      expect(analytics.streaks(resolve(repaired)).longest, 7);
    });
  });

  group('editing a past day', () {
    test('changing a completion to a skip removes it from the denominator', () {
      final asDone = analytics.summarize(resolve([event(d(2026, 8, 5))]));
      final asSkip = analytics.summarize(
        resolve([event(d(2026, 8, 5), kind: TrackingKind.skipped)]),
      );

      expect(asDone.eligible, asSkip.eligible + 1);
      expect(asSkip.skipped, 1);
      expect(asSkip.done, 0);
    });

    test('downgrading a completion to partial halves its credit', () {
      final done = analytics.summarize(resolve([event(d(2026, 8, 5))]));
      final partial = analytics.summarize(
        resolve([event(d(2026, 8, 5), kind: TrackingKind.partial)]),
      );
      expect(done.weightedCompletion - partial.weightedCompletion,
          closeTo(0.5, 1e-9));
      expect(done.eligible, partial.eligible);
    });

    test('removing an event returns the day to missed', () {
      final withEvent = resolve([event(d(2026, 8, 5), id: 'x')]);
      final without = resolve(const []);
      expect(withEvent[4].status, OccurrenceStatus.done);
      expect(without[4].status, OccurrenceStatus.missed);
    });
  });

  group('historical integrity', () {
    test('a future schedule change leaves past analytics byte-identical', () {
      final events = [
        for (final day in [1, 2, 3, 5, 8, 13, 21])
          event(d(2026, 8, day), id: 'e$day'),
      ];

      final beforeChange = analytics.summarize(resolve(events));
      final beforeStreaks = analytics.streaks(resolve(events));

      // The user switches to 3x/week starting in October.
      final versioned = [
        schedule(
          id: 'v1',
          frequency: const Frequency.daily(),
          from: d(2026, 8, 1),
          to: d(2026, 9, 30),
        ),
        schedule(
          id: 'v2',
          frequency: const Frequency.timesPerWeek(target: 3),
          from: d(2026, 10, 1),
        ),
      ];
      final afterChange =
          analytics.summarize(resolve(events, schedules: versioned));
      final afterStreaks =
          analytics.streaks(resolve(events, schedules: versioned));

      expect(afterChange.eligible, beforeChange.eligible);
      expect(afterChange.done, beforeChange.done);
      expect(afterChange.missed, beforeChange.missed);
      expect(afterChange.weightedCompletion,
          closeTo(beforeChange.weightedCompletion, 1e-12));
      expect(afterChange.percent, beforeChange.percent);
      expect(afterStreaks.longest, beforeStreaks.longest);
      expect(afterStreaks.averageRecoveryDays,
          beforeStreaks.averageRecoveryDays);
    });

    test('resolution is a pure function of canonical records', () {
      // Same inputs, independently resolved twice, must agree exactly. This is
      // what makes materialised rollups safe to rebuild from scratch later.
      final events = [
        for (final day in [2, 4, 6, 9, 14])
          event(d(2026, 8, day), id: 'e$day'),
      ];
      final first = resolve(events);
      final second = resolve(events.reversed.toList());

      expect(
        first.map((r) => '${r.occurrence.span}:${r.status.name}:${r.credit}'),
        second.map((r) => '${r.occurrence.span}:${r.status.name}:${r.credit}'),
      );
    });
  });
}
