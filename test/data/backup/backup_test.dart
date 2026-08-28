import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/resolution.dart';
import 'package:riyaz/app/settings.dart';
import 'package:riyaz/data/backup/backup_codec.dart';
import 'package:riyaz/data/backup/backup_document.dart';
import 'package:riyaz/data/backup/backup_service.dart';
import 'package:riyaz/data/db/app_database.dart';
import 'package:riyaz/data/repository/rollup_repository.dart';
import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/data/seed/seed_loader.dart';
import 'package:riyaz/domain/accounting/accounting_engine.dart';
import 'package:riyaz/domain/analytics/analytics_engine.dart';
import 'package:riyaz/domain/model/frequency.dart';
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

  late AppDatabase db;
  late TrackingRepository tracking;
  late RollupRepository rollups;
  late ResolutionService resolution;
  late BackupService backup;

  const codec = BackupCodec();
  const analytics = AnalyticsEngine();
  final clock = FixedClock.iso('2026-08-28T10:00:00+05:30');
  final year = CivilDateRange(d(2025, 8, 29), d(2026, 8, 28));

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
    backup = BackupService(
      database: db,
      repository: tracking,
      rollups: rollups,
      clock: clock,
      settings: const AppSettings(),
    );
  });
  tearDown(() => db.close());

  Future<String> seedSimple() async {
    final id = await tracking.createCommitment(
      name: 'Running',
      frequency: const Frequency.daily(),
      startedOn: d(2026, 8, 1),
      nowUtc: clock.nowUtc(),
      icon: '🏃',
    );
    for (final day in [1, 2, 3, 5, 8]) {
      await tracking.record(
        commitmentId: id,
        date: d(2026, 8, day),
        kind: TrackingKind.done,
        nowUtc: clock.nowUtc(),
        label: 'done',
      );
    }
    await tracking.record(
      commitmentId: id,
      date: d(2026, 8, 10),
      kind: TrackingKind.skipped,
      nowUtc: clock.nowUtc(),
      label: 'skip',
    );
    return id;
  }

  group('codec', () {
    test('every field survives a round trip', () async {
      await seedSimple();
      final doc = await backup.buildDocument();
      final decoded = codec.decode(codec.encode(doc));

      expect(decoded.version, BackupDocument.currentVersion);
      expect(decoded.timezoneName, 'Asia/Kolkata');
      expect(decoded.dayBoundaryHour, 4);
      expect(decoded.commitments.single.name, 'Running');
      expect(decoded.commitments.single.icon, '🏃');
      expect(decoded.commitments.single.startedOn, d(2026, 8, 1));
      expect(decoded.events, hasLength(6));
      expect(
        decoded.events.where((e) => e.kind == TrackingKind.skipped),
        hasLength(1),
      );
    });

    test('every frequency shape survives', () async {
      const shapes = [
        Frequency.daily(target: 3),
        Frequency.weekdays(days: {1, 3, 5}, target: 2),
        Frequency.everyNDays(n: 4),
        Frequency.timesPerWeek(target: 4),
        Frequency.timesPerMonth(target: 2),
      ];
      for (final shape in shapes) {
        await tracking.createCommitment(
          name: 'C',
          frequency: shape,
          startedOn: d(2026, 8, 1),
          nowUtc: clock.nowUtc(),
        );
      }
      final decoded = codec.decode(codec.encode(await backup.buildDocument()));
      expect(
        decoded.schedules.map((s) => s.frequency).toSet(),
        shapes.toSet(),
      );
    });

    test('dates stay human-readable in the file', () async {
      await seedSimple();
      final json = codec.encode(await backup.buildDocument());
      expect(json, contains('"startedOn": "2026-08-01"'));
      expect(json, contains('"accountingDate": "2026-08-01"'));
    });
  });

  group('validation refuses what it cannot vouch for', () {
    test('rejects non-JSON', () {
      expect(
        () => backup.validate('not json at all'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('rejects a foreign file that happens to be JSON', () {
      expect(
        () => backup.validate('{"hello":"world"}'),
        throwsA(predicate(
          (e) => e is BackupFormatException &&
              e.message.contains('does not look like a Riyaz backup'),
        )),
      );
    });

    test('refuses a backup from a newer app version', () {
      const future = '{"format":"riyaz.backup","version":99,'
          '"exportedAt":"2026-01-01T00:00:00Z","settings":'
          '{"timezone":"Asia/Kolkata","dayBoundaryHour":4,"weekStartsOn":1}}';
      expect(
        () => backup.validate(future),
        throwsA(predicate((e) =>
            e is BackupFormatException && e.message.contains('newer version'))),
      );
    });

    test('rejects a malformed date rather than guessing', () async {
      await seedSimple();
      final json = codec
          .encode(await backup.buildDocument())
          .replaceFirst('"2026-08-01"', '"01/08/2026"');
      expect(
        () => backup.validate(json),
        throwsA(predicate((e) =>
            e is BackupFormatException && e.message.contains('not a valid date'))),
      );
    });

    test('rejects an unknown enum value', () async {
      await seedSimple();
      final json = codec
          .encode(await backup.buildDocument())
          .replaceFirst('"kind": "done"', '"kind": "teleported"');
      expect(
        () => backup.validate(json),
        throwsA(predicate((e) =>
            e is BackupFormatException && e.message.contains('teleported'))),
      );
    });

    test('warns about orphans without refusing the file', () async {
      await seedSimple();
      final json = codec
          .encode(await backup.buildDocument())
          .replaceFirst(RegExp(r'"commitments": \[[\s\S]*?\n  \]'),
              '"commitments": []');
      final preview = backup.validate(json);
      expect(preview.warnings.any((w) => w.contains('will be skipped')), isTrue);
    });

    test('warns when the backup timezone differs from the device', () async {
      await seedSimple();
      final json = codec
          .encode(await backup.buildDocument())
          .replaceFirst('"Asia/Kolkata"', '"America/New_York"');
      final preview = backup.validate(json);
      expect(
        preview.warnings.any((w) => w.contains('America/New_York')),
        isTrue,
      );
    });
  });

  group('import', () {
    test('replace restores onto an empty database', () async {
      await seedSimple();
      final json = await backup.exportJson();

      await db.delete(db.commitments).go();
      expect((await tracking.readAll()).commitments, isEmpty);

      final result = await backup.import(
        backup.validate(json).document,
        mode: ImportMode.replace,
      );
      expect(result.inserted, greaterThan(0));
      final restored = await tracking.readAll();
      expect(restored.commitments, hasLength(1));
      expect(restored.events, hasLength(6));
    });

    test('merge is idempotent — importing twice changes nothing', () async {
      await seedSimple();
      final json = await backup.exportJson();
      final before = await tracking.readAll();

      final first = await backup.import(backup.validate(json).document);
      expect(first.inserted, 0);
      expect(first.skipped, greaterThan(0));

      final second = await backup.import(backup.validate(json).document);
      expect(second.inserted, 0);

      final after = await tracking.readAll();
      expect(after.commitments.length, before.commitments.length);
      expect(after.events.length, before.events.length);
    });

    test('merge adds only what is missing', () async {
      await seedSimple();
      final json = await backup.exportJson();
      // Drop half the events, then merge the file back in.
      final events = (await tracking.readAll()).events;
      await tracking.clear(
        commitmentId: events.first.commitmentId,
        date: events.first.accountingDate,
        label: 'clear',
      );
      final reduced = (await tracking.readAll()).events.length;

      final result = await backup.import(backup.validate(json).document);
      expect(result.inserted, 6 - reduced);
      expect((await tracking.readAll()).events, hasLength(6));
    });

    test('orphans are dropped rather than failing the whole import', () async {
      await seedSimple();
      final json = codec
          .encode(await backup.buildDocument())
          .replaceFirst(RegExp(r'"commitments": \[[\s\S]*?\n  \]'),
              '"commitments": []');
      final result = await backup.import(
        backup.validate(json).document,
        mode: ImportMode.replace,
      );
      expect(result.dropped, greaterThan(0));
      expect(result.inserted, 0);
    });

    test('a failed import leaves the database untouched', () async {
      await seedSimple();
      final before = await tracking.readAll();
      expect(
        () => backup.validate('{"format":"riyaz.backup","version":1}'),
        throwsA(isA<BackupFormatException>()),
      );
      final after = await tracking.readAll();
      expect(after.commitments.length, before.commitments.length);
      expect(after.events.length, before.events.length);
    });
  });

  group('the round trip that matters', () {
    test('export, wipe, import — every analytic number is identical',
        () async {
      // A full synthetic year: 20 commitments, schedule changes, pauses,
      // archived commitments, partials and skips.
      const seeder = SyntheticSeeder();
      await SeedLoader(db).load(
        seeder.generate(endingOn: d(2026, 8, 28), seed: 7),
      );

      final before = await resolution.read(year);
      final summaryBefore = analytics.summarize(before.all);
      final streaksBefore = {
        for (final c in before.commitments)
          c.id: analytics.streaks(before.forCommitment(c.id)),
      };

      final json = await backup.exportJson();
      expect(json.length, greaterThan(10000));

      // Simulate a lost phone.
      await db.delete(db.commitments).go();
      await db.delete(db.occurrenceRollups).go();
      expect((await resolution.read(year)).all, isEmpty);

      final preview = backup.validate(json);
      await backup.import(preview.document, mode: ImportMode.replace);

      final after = await resolution.read(year);
      final summaryAfter = analytics.summarize(after.all);

      expect(after.commitments.length, before.commitments.length);
      expect(summaryAfter.done, summaryBefore.done);
      expect(summaryAfter.partial, summaryBefore.partial);
      expect(summaryAfter.missed, summaryBefore.missed);
      expect(summaryAfter.skipped, summaryBefore.skipped);
      expect(summaryAfter.eligible, summaryBefore.eligible);
      expect(
        summaryAfter.weightedCompletion,
        closeTo(summaryBefore.weightedCompletion, 1e-9),
      );
      expect(summaryAfter.percent, summaryBefore.percent);

      // Per-commitment momentum must survive too, not just the totals.
      for (final c in after.commitments) {
        final expected = streaksBefore[c.id]!;
        final actual = analytics.streaks(after.forCommitment(c.id));
        expect(actual.longest, expected.longest, reason: 'longest for ${c.id}');
        expect(actual.current, expected.current, reason: 'current for ${c.id}');
        expect(
          actual.averageRecoveryDays,
          expected.averageRecoveryDays,
          reason: 'recovery for ${c.id}',
        );
      }
    });

    test('rollups rebuild correctly after a restore', () async {
      const seeder = SyntheticSeeder();
      await SeedLoader(db).load(
        seeder.generate(endingOn: d(2026, 8, 28), seed: 3),
      );
      await rollups.markStale(d(2025, 8, 29));
      await rollups.ensureFresh(year);
      final before = await rollups.summaryFor(year);

      final json = await backup.exportJson();
      await db.delete(db.commitments).go();
      await db.delete(db.occurrenceRollups).go();
      await backup.import(
        backup.validate(json).document,
        mode: ImportMode.replace,
      );
      await rollups.ensureFresh(year);

      final after = await rollups.summaryFor(year);
      expect(after.percent, before.percent);
      expect(after.eligible, before.eligible);
      expect(after.done, before.done);
    });
  });
}
