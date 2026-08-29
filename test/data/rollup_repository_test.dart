import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/resolution.dart';
import 'package:riyaz/data/db/app_database.dart';
import 'package:riyaz/data/repository/rollup_repository.dart';
import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/domain/accounting/accounting_engine.dart';
import 'package:riyaz/domain/analytics/analytics_engine.dart';
import 'package:riyaz/domain/analytics/scoring.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/recurrence/recurrence_engine.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/domain/time/clock.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/dates.dart';
import '../support/fixtures.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late TrackingRepository tracking;
  late RollupRepository rollups;
  late ResolutionService resolution;
  const analytics = AnalyticsEngine();

  final clock = FixedClock.iso('2026-08-28T10:00:00+05:30');
  final year = CivilDateRange(d(2025, 9, 1), d(2026, 8, 28));

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tracking = TrackingRepository(db);
    final calendar = calendarFor('Asia/Kolkata');
    resolution = ResolutionService(
      repository: tracking,
      accounting: AccountingEngine(
        calendar: calendar,
        recurrence: RecurrenceEngine(calendar),
      ),
      clock: clock,
    );
    rollups = RollupRepository(db, resolution);
    tracking.onWrite = rollups.markStale;
  });
  tearDown(() => db.close());

  Future<String> seed({
    Frequency frequency = const Frequency.daily(),
    List<int> doneInAugust = const [],
  }) async {
    final id = await tracking.createCommitment(
      name: 'Running',
      frequency: frequency,
      startedOn: d(2026, 8, 1),
      nowUtc: clock.nowUtc(),
    );
    for (final day in doneInAugust) {
      await tracking.record(
        commitmentId: id,
        date: d(2026, 8, day),
        kind: TrackingKind.done,
        nowUtc: clock.nowUtc(),
        label: 'done',
      );
    }
    return id;
  }

  group('correctness', () {
    test('rollup aggregation equals direct resolution', () async {
      await seed(doneInAugust: [1, 2, 3, 5, 8, 13, 21]);
      await rollups.ensureFresh(year);

      final fromRollups = await rollups.summaryFor(year);
      final direct = analytics.summarize((await resolution.read(year)).all);

      expect(fromRollups.done, direct.done);
      expect(fromRollups.partial, direct.partial);
      expect(fromRollups.missed, direct.missed);
      expect(fromRollups.skipped, direct.skipped);
      expect(fromRollups.eligible, direct.eligible);
      expect(
        fromRollups.weightedCompletion,
        closeTo(direct.weightedCompletion, 1e-9),
      );
      expect(fromRollups.percent, direct.percent);
    });

    test('period commitments aggregate identically', () async {
      await seed(
        frequency: const Frequency.timesPerWeek(target: 4),
        doneInAugust: [3, 4, 6, 10, 11, 17],
      );
      await rollups.ensureFresh(year);

      final fromRollups = await rollups.summaryFor(year);
      final direct = analytics.summarize((await resolution.read(year)).all);
      expect(fromRollups.percent, direct.percent);
      expect(fromRollups.eligible, direct.eligible);
    });

    test('rebuilding from scratch reproduces the same numbers', () async {
      await seed(doneInAugust: [1, 4, 9, 16, 25]);
      await rollups.ensureFresh(year);
      final before = await rollups.summaryFor(year);

      // Throw the derived data away entirely — it must be reconstructible.
      await db.delete(db.occurrenceRollups).go();
      await (db.delete(db.settings)).go();
      await rollups.ensureFresh(year);

      final after = await rollups.summaryFor(year);
      expect(after.percent, before.percent);
      expect(after.eligible, before.eligible);
      expect(after.done, before.done);
    });
  });

  group('the year view does not scan raw events', () {
    test('summaries survive the events being deleted', () async {
      await seed(doneInAugust: [1, 2, 3, 5, 8, 13, 21]);
      await rollups.ensureFresh(year);
      final before = await rollups.summaryFor(year);

      // Direct proof: with every raw event gone, an implementation that
      // re-derived from events would collapse to zero. Rollups do not.
      await db.delete(db.trackingEvents).go();

      final after = await rollups.summaryFor(year);
      expect(after.done, before.done);
      expect(after.percent, before.percent);
      expect(after.done, greaterThan(0));
    });

    test('monthly buckets come from rollups alone', () async {
      await seed(doneInAugust: [1, 2, 3, 4, 5]);
      await rollups.ensureFresh(year);
      await db.delete(db.trackingEvents).go();

      final months = await rollups.bucketed(
        range: year,
        bucketOf: (date) => date.startOfMonth,
      );
      expect(months.keys, contains(d(2026, 8, 1)));
      expect(months[d(2026, 8, 1)]!.done, 5);
    });
  });

  group('the logic that built a rollup is part of its validity', () {
    // A rollup caches a resolution result, so it is only good while the rules
    // that produced it hold. The watermark sees changed data and is blind to a
    // changed rule; without the version stamp these reads all serve numbers
    // the current engine would never produce.
    RollupRepository withWeights(ScoringWeights weights) {
      final calendar = calendarFor('Asia/Kolkata');
      return RollupRepository(
        db,
        ResolutionService(
          repository: tracking,
          accounting: AccountingEngine(
            calendar: calendar,
            recurrence: RecurrenceEngine(calendar),
            weights: weights,
          ),
          clock: clock,
        ),
      );
    }

    test('changing the scoring weights rebuilds the cache', () async {
      final id = await seed(doneInAugust: [1, 2, 3]);
      await tracking.record(
        commitmentId: id,
        date: d(2026, 8, 4),
        kind: TrackingKind.partial,
        nowUtc: clock.nowUtc(),
        label: 'partial',
      );
      await rollups.ensureFresh(year);
      expect((await rollups.summaryFor(year)).weightedCompletion, 3.5);

      // Same database, same events, different rule.
      final quarter = withWeights(const ScoringWeights(partial: 0.25));
      await quarter.ensureFresh(year);

      expect((await quarter.summaryFor(year)).weightedCompletion, 3.25,
          reason: 'the cache was built under partial = 0.5');
    });

    test('a database written before the stamp existed is rebuilt', () async {
      await seed(doneInAugust: [1, 2]);
      await rollups.ensureFresh(year);

      // An upgrade from a build with no version marker: the rows on disk came
      // from rules this code cannot identify, so they cannot be trusted.
      await (db.delete(db.settings)
            ..where((t) => t.key.equals('rollup.logicVersion')))
          .go();
      await db.delete(db.occurrenceRollups).go();

      await rollups.ensureFresh(year);
      expect((await rollups.summaryFor(year)).done, 2,
          reason: 'a missing stamp must force a rebuild, not serve nothing');
    });

    test('an unchanged stamp does not rebuild', () async {
      await seed(doneInAugust: [1, 2]);
      await rollups.ensureFresh(year);

      // Deleting the events would empty any rebuild. The summary surviving is
      // what proves the second call reused the cache rather than recomputing.
      await db.delete(db.trackingEvents).go();
      await rollups.ensureFresh(year);

      expect((await rollups.summaryFor(year)).done, 2);
    });
  });

  group('invalidation', () {
    test('a new completion is reflected on the next read', () async {
      final id = await seed(doneInAugust: [1, 2]);
      await rollups.ensureFresh(year);
      expect((await rollups.summaryFor(year)).done, 2);

      await tracking.record(
        commitmentId: id,
        date: d(2026, 8, 20),
        kind: TrackingKind.done,
        nowUtc: clock.nowUtc(),
        label: 'done',
      );
      await rollups.ensureFresh(year);
      expect((await rollups.summaryFor(year)).done, 3);
    });

    test('backfilling a past day invalidates from that day', () async {
      final id = await seed(doneInAugust: [20, 21]);
      await rollups.ensureFresh(year);
      final before = await rollups.summaryFor(year);

      await tracking.record(
        commitmentId: id,
        date: d(2026, 8, 3),
        kind: TrackingKind.done,
        nowUtc: clock.nowUtc(),
        label: 'backfill',
      );
      await rollups.ensureFresh(year);

      final after = await rollups.summaryFor(year);
      expect(after.done, before.done + 1);
      expect(after.missed, before.missed - 1);
    });

    test('an undo is reflected too', () async {
      final id = await seed(doneInAugust: [10]);
      await rollups.ensureFresh(year);

      final token = await tracking.record(
        commitmentId: id,
        date: d(2026, 8, 11),
        kind: TrackingKind.done,
        nowUtc: clock.nowUtc(),
        label: 'done',
      );
      await rollups.ensureFresh(year);
      expect((await rollups.summaryFor(year)).done, 2);

      await tracking.undo(token);
      await rollups.ensureFresh(year);
      expect((await rollups.summaryFor(year)).done, 1);
    });

    test('a clean read does no rebuild work', () async {
      await seed(doneInAugust: [1]);
      await rollups.ensureFresh(year);

      // With no write in between, the stale marker stays cleared.
      await rollups.ensureFresh(year);
      final marker = await (db.select(db.settings)
            ..where((t) => t.key.equals('rollup.staleFrom')))
          .getSingleOrNull();
      expect(marker, isNull);
    });
  });
}
