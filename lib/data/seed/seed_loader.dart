import 'package:drift/drift.dart';
import 'package:riyaz/domain/seed/synthetic_seeder.dart';

import '../db/app_database.dart';
import '../db/mappers.dart';

/// Writes a generated dataset into the database.
///
/// Development only. Kept out of `lib/domain/` because it touches storage, and
/// out of the seeder itself because generating data and persisting it are
/// separate concerns — the generator stays pure and testable.
class SeedLoader {
  const SeedLoader(this._db);

  final AppDatabase _db;

  Future<void> load(SyntheticDataset data, {bool wipeFirst = true}) async {
    await _db.transaction(() async {
      if (wipeFirst) {
        await _db.delete(_db.commitments).go();
        await _db.delete(_db.occurrenceRollups).go();
      }

      var order = 0;
      for (final c in data.commitments) {
        await _db.into(_db.commitments).insert(CommitmentsCompanion.insert(
              id: c.id,
              name: c.name,
              startedOn: c.startedOn,
              state: c.state,
              createdAt: DateTime.utc(2026),
              icon: Value(c.icon),
              archivedOn: Value(c.archivedOn),
              sortOrder: Value(order++),
            ));
      }
      for (final s in data.schedules) {
        final columns = frequencyToColumns(s.frequency);
        await _db
            .into(_db.commitmentSchedules)
            .insert(CommitmentSchedulesCompanion.insert(
              id: s.id,
              commitmentId: s.commitmentId,
              effectiveFrom: s.effectiveFrom,
              effectiveTo: Value(s.effectiveTo),
              frequencyType: columns.type,
              target: Value(columns.target),
              daysOfWeekMask: Value(columns.daysMask),
              everyNDays: Value(columns.everyN),
              targetMinutes: Value(s.targetMinutes),
            ));
      }
      for (final p in data.pauses) {
        await _db.into(_db.pausePeriods).insert(PausePeriodsCompanion.insert(
              id: p.id,
              commitmentId: p.commitmentId,
              fromDay: p.from,
              toDay: Value(p.to),
            ));
      }
      for (final e in data.events) {
        await _db.into(_db.trackingEvents).insert(
              TrackingEventsCompanion.insert(
                id: e.id,
                commitmentId: e.commitmentId,
                accountingDate: e.accountingDate,
                recordedAtUtc: e.recordedAtUtc,
                kind: e.kind,
                count: Value(e.count),
                minutes: Value(e.minutes),
                note: Value(e.note),
              ),
            );
      }
    });
  }
}
