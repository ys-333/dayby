import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/data/db/app_database.dart';
import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/time/civil_date.dart';

import '../support/dates.dart';

void main() {
  late AppDatabase db;
  late TrackingRepository repo;

  final today = d(2026, 8, 28);
  final now = DateTime.utc(2026, 8, 28, 4, 30);
  final week = CivilDateRange(d(2026, 8, 24), d(2026, 8, 30));

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TrackingRepository(db);
  });
  tearDown(() => db.close());

  Future<String> newCommitment({
    Frequency frequency = const Frequency.daily(),
    String name = 'Running',
  }) =>
      repo.createCommitment(
        name: name,
        frequency: frequency,
        startedOn: d(2026, 8, 1),
        nowUtc: now,
        icon: '🏃',
      );

  group('round-trip', () {
    test('a commitment comes back as a domain model with its schedule', () async {
      final id = await newCommitment();
      final snap = await repo.read(week);

      expect(snap.commitments, hasLength(1));
      final c = snap.commitments.single;
      expect(c.id, id);
      expect(c.name, 'Running');
      expect(c.icon, '🏃');
      expect(c.startedOn, d(2026, 8, 1));
      expect(c.state, CommitmentState.active);

      final schedules = snap.schedulesFor(id);
      expect(schedules, hasLength(1));
      expect(schedules.single.frequency, const Frequency.daily());
    });

    test('every frequency shape survives storage', () async {
      const shapes = [
        Frequency.daily(target: 2),
        Frequency.weekdays(days: {1, 3, 5}, target: 1),
        Frequency.everyNDays(n: 4),
        Frequency.timesPerWeek(target: 4),
        Frequency.timesPerMonth(target: 2),
      ];
      for (final shape in shapes) {
        final id = await newCommitment(frequency: shape, name: 'x');
        final snap = await repo.read(week);
        expect(snap.schedulesFor(id).single.frequency, shape,
            reason: 'round-trip failed for $shape');
      }
    });

    test('civil dates survive as civil dates, not shifted instants', () async {
      final id = await newCommitment();
      await repo.record(
        commitmentId: id,
        date: d(2026, 8, 25),
        kind: TrackingKind.done,
        nowUtc: now,
        label: 'done',
      );
      final snap = await repo.read(week);
      expect(snap.events.single.accountingDate, d(2026, 8, 25));
      expect(snap.events.single.recordedAtUtc.isUtc, isTrue);
    });

    test('the range filter excludes events outside it', () async {
      final id = await newCommitment();
      for (final day in [d(2026, 8, 20), d(2026, 8, 25), d(2026, 9, 5)]) {
        await repo.record(
          commitmentId: id,
          date: day,
          kind: TrackingKind.done,
          nowUtc: now,
          label: 'done',
        );
      }
      final snap = await repo.read(week);
      expect(snap.events.map((e) => e.accountingDate), [d(2026, 8, 25)]);
    });
  });

  group('undo', () {
    test('undoing a completion returns the day to empty', () async {
      final id = await newCommitment();
      final token = await repo.record(
        commitmentId: id,
        date: today,
        kind: TrackingKind.done,
        nowUtc: now,
        label: 'Running marked done',
      );
      expect((await repo.read(week)).events, hasLength(1));

      await repo.undo(token);
      expect((await repo.read(week)).events, isEmpty);
    });

    test('undo restores the exact prior state, not merely a deletion', () async {
      final id = await newCommitment(frequency: const Frequency.daily(target: 3));
      // Two increments already recorded.
      await repo.record(
        commitmentId: id,
        date: today,
        kind: TrackingKind.done,
        nowUtc: now,
        label: '+1',
      );
      await repo.record(
        commitmentId: id,
        date: today,
        kind: TrackingKind.done,
        nowUtc: now,
        label: '+1',
      );
      // A skip wipes the day...
      final token = await repo.record(
        commitmentId: id,
        date: today,
        kind: TrackingKind.skipped,
        nowUtc: now,
        label: 'Running skipped',
      );
      final afterSkip = await repo.read(week);
      expect(afterSkip.events, hasLength(1));
      expect(afterSkip.events.single.kind, TrackingKind.skipped);

      // ...and undo brings both completions back.
      await repo.undo(token);
      final restored = await repo.read(week);
      expect(restored.events, hasLength(2));
      expect(
        restored.events.every((e) => e.kind == TrackingKind.done),
        isTrue,
      );
    });

    test('undoing a clear restores what was cleared', () async {
      final id = await newCommitment();
      await repo.record(
        commitmentId: id,
        date: today,
        kind: TrackingKind.partial,
        nowUtc: now,
        label: 'partial',
      );
      final token = await repo.clear(
        commitmentId: id,
        date: today,
        label: 'cleared',
      );
      expect((await repo.read(week)).events, isEmpty);

      await repo.undo(token);
      final restored = (await repo.read(week)).events;
      expect(restored, hasLength(1));
      expect(restored.single.kind, TrackingKind.partial);
    });

    test('undo touches only the day it describes', () async {
      final id = await newCommitment();
      await repo.record(
        commitmentId: id,
        date: d(2026, 8, 26),
        kind: TrackingKind.done,
        nowUtc: now,
        label: 'done',
      );
      final token = await repo.record(
        commitmentId: id,
        date: d(2026, 8, 27),
        kind: TrackingKind.done,
        nowUtc: now,
        label: 'done',
      );
      await repo.undo(token);

      final events = (await repo.read(week)).events;
      expect(events, hasLength(1));
      expect(events.single.accountingDate, d(2026, 8, 26));
    });
  });

  group('semantics', () {
    test('a skip replaces the day rather than coexisting with it', () async {
      final id = await newCommitment();
      await repo.record(
        commitmentId: id,
        date: today,
        kind: TrackingKind.done,
        nowUtc: now,
        label: 'done',
      );
      await repo.record(
        commitmentId: id,
        date: today,
        kind: TrackingKind.skipped,
        nowUtc: now,
        label: 'skip',
      );
      final events = (await repo.read(week)).events;
      expect(events, hasLength(1));
      expect(events.single.kind, TrackingKind.skipped);
    });

    test('increments accumulate on the same day', () async {
      final id = await newCommitment(frequency: const Frequency.daily(target: 3));
      for (var i = 0; i < 3; i++) {
        await repo.record(
          commitmentId: id,
          date: today,
          kind: TrackingKind.done,
          nowUtc: now,
          label: '+1',
        );
      }
      expect((await repo.read(week)).events, hasLength(3));
    });

    test('archiving preserves history', () async {
      final id = await newCommitment();
      await repo.record(
        commitmentId: id,
        date: d(2026, 8, 25),
        kind: TrackingKind.done,
        nowUtc: now,
        label: 'done',
      );
      await repo.archiveCommitment(id, today);

      final snap = await repo.read(week);
      expect(snap.commitments.single.state, CommitmentState.archived);
      expect(snap.commitments.single.archivedOn, today);
      expect(snap.events, hasLength(1), reason: 'history must survive archive');
      // The flag is decoration; this is the part the engine reads.
      expect(snap.schedulesFor(id).single.effectiveTo, today,
          reason: 'an archived commitment with an open schedule keeps '
              'expecting occurrences forever');
    });

    test('unarchiving reopens the schedule archiving closed', () async {
      final id = await newCommitment();
      await repo.archiveCommitment(id, today);
      await repo.unarchiveCommitment(id);

      final snap = await repo.read(week);
      expect(snap.commitments.single.state, CommitmentState.active);
      expect(snap.commitments.single.archivedOn, isNull);
      expect(snap.schedulesFor(id).single.effectiveTo, isNull,
          reason: 'a commitment back in the list must expect occurrences '
              'again, or it is archived in everything but name');
    });

    test('deleting a commitment cascades to its events', () async {
      final id = await newCommitment();
      await repo.record(
        commitmentId: id,
        date: today,
        kind: TrackingKind.done,
        nowUtc: now,
        label: 'done',
      );
      await (db.delete(db.commitments)..where((t) => t.id.equals(id))).go();

      final snap = await repo.read(week);
      expect(snap.commitments, isEmpty);
      expect(snap.events, isEmpty, reason: 'foreign keys must be enforced');
    });

    test('pauses round-trip', () async {
      final id = await newCommitment();
      await repo.pauseCommitment(
        commitmentId: id,
        from: d(2026, 8, 26),
        to: d(2026, 8, 28),
      );
      final pauses = (await repo.read(week)).pausesFor(id);
      expect(pauses, hasLength(1));
      expect(pauses.single.from, d(2026, 8, 26));
      expect(pauses.single.to, d(2026, 8, 28));
    });
  });

  group('watch', () {
    test('emits immediately and again after a write', () async {
      final id = await newCommitment();
      final seen = <int>[];
      final sub = repo.watch(week).listen((s) => seen.add(s.events.length));

      await Future<void>.delayed(Duration.zero);
      await repo.record(
        commitmentId: id,
        date: today,
        kind: TrackingKind.done,
        nowUtc: now,
        label: 'done',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(seen.first, 0);
      expect(seen.last, 1);
    });
  });
}
