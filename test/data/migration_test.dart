import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/data/db/app_database.dart';
import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/time/accounting_calendar.dart';
import 'package:riyaz/domain/model/commitment.dart';

import '../support/dates.dart';

/// Schema v1, verbatim as drift generated it before `occurrence_rollups`
/// existed. Copied from a real v1 database rather than written from memory —
/// a migration test against an approximated old schema proves nothing.
const List<String> _v1Schema = [
  'CREATE TABLE "commitments" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, '
      '"description" TEXT NULL, "icon" TEXT NULL, "category_id" TEXT NULL, '
      '"started_on" INTEGER NOT NULL, "state" INTEGER NOT NULL, '
      '"archived_on" INTEGER NULL, "sort_order" INTEGER NOT NULL DEFAULT 0, '
      '"created_at" INTEGER NOT NULL, PRIMARY KEY ("id"));',
  'CREATE TABLE "commitment_schedules" ("id" TEXT NOT NULL, '
      '"commitment_id" TEXT NOT NULL REFERENCES commitments (id) ON DELETE CASCADE, '
      '"effective_from" INTEGER NOT NULL, "effective_to" INTEGER NULL, '
      '"frequency_type" INTEGER NOT NULL, "target" INTEGER NOT NULL DEFAULT 1, '
      '"days_of_week_mask" INTEGER NOT NULL DEFAULT 0, "every_n_days" INTEGER NULL, '
      '"target_minutes" INTEGER NULL, PRIMARY KEY ("id"));',
  'CREATE TABLE "tracking_events" ("id" TEXT NOT NULL, '
      '"commitment_id" TEXT NOT NULL REFERENCES commitments (id) ON DELETE CASCADE, '
      '"accounting_date" INTEGER NOT NULL, "recorded_at_utc" INTEGER NOT NULL, '
      '"kind" INTEGER NOT NULL, "count" INTEGER NOT NULL DEFAULT 1, '
      '"minutes" INTEGER NULL, "note" TEXT NULL, PRIMARY KEY ("id"));',
  'CREATE TABLE "pause_periods" ("id" TEXT NOT NULL, '
      '"commitment_id" TEXT NOT NULL REFERENCES commitments (id) ON DELETE CASCADE, '
      '"from_day" INTEGER NOT NULL, "to_day" INTEGER NOT NULL, PRIMARY KEY ("id"));',
  'CREATE TABLE "settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, '
      'PRIMARY KEY ("key"));',
];

/// Opens an [AppDatabase] on a database that already contains schema v1 and
/// real data, so opening it exercises the actual v1 → v2 migration path.
///
/// Uses drift's `setup` hook rather than a direct sqlite3 dependency: the
/// callback hands over the raw database before drift inspects its version, so
/// the v1 schema can be laid down first without declaring a new package.
AppDatabase _openMigratedFromV1() => AppDatabase(
      NativeDatabase.memory(setup: (raw) {
        for (final ddl in _v1Schema) {
          raw.execute(ddl);
        }
        raw.execute('PRAGMA user_version = 1');

        raw.execute(
          'INSERT INTO commitments (id, name, icon, started_on, state, '
          'sort_order, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
          ['c1', 'Running', '🏃', d(2026, 8, 1).epochDay, 0, 0, 1756000000000],
        );
        raw.execute(
          'INSERT INTO commitment_schedules (id, commitment_id, '
          'effective_from, frequency_type, target) VALUES (?, ?, ?, ?, ?)',
          ['s1', 'c1', d(2026, 8, 1).epochDay, 0, 1],
        );
        for (final day in [1, 2, 3, 5, 8]) {
          raw.execute(
            'INSERT INTO tracking_events (id, commitment_id, accounting_date, '
            'recorded_at_utc, kind, count, note) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [
              'e$day',
              'c1',
              d(2026, 8, day).epochDay,
              1756000000000,
              0,
              1,
              day == 3 ? 'felt good — 5km' : null,
            ],
          );
        }
        raw.execute(
          'INSERT INTO pause_periods (id, commitment_id, from_day, to_day) '
          'VALUES (?, ?, ?, ?)',
          ['p1', 'c1', d(2026, 8, 20).epochDay, d(2026, 8, 22).epochDay],
        );
      }),
    );

Future<int> _userVersion(AppDatabase db) async {
  final row = await db.customSelect('PRAGMA user_version').getSingle();
  return row.data.values.first as int;
}

void main() {
  test('a v1 database migrates to v2 with every record intact', () async {
    final db = _openMigratedFromV1();
    addTearDown(db.close);

    // Opening runs the migration.
    final snapshot = await TrackingRepository(db).readAll();

    expect(await _userVersion(db), 2, reason: 'schema version must advance');

    // Nothing lost. This is the whole point: the database holds years of
    // history that exists nowhere else, so a schema bump must never drop it.
    expect(snapshot.commitments, hasLength(1));
    final c = snapshot.commitments.single;
    expect(c.name, 'Running');
    expect(c.icon, '🏃');
    expect(c.startedOn, d(2026, 8, 1));
    expect(c.state, CommitmentState.active);

    expect(snapshot.schedulesFor('c1'), hasLength(1));
    expect(snapshot.pausesFor('c1'), hasLength(1));
    expect(snapshot.events, hasLength(5));
    expect(
      snapshot.events.firstWhere((e) => e.id == 'e3').note,
      'felt good — 5km',
      reason: 'unicode notes must survive a migration',
    );
  });

  test('the v2 rollup table is created empty and is usable', () async {
    final db = _openMigratedFromV1();
    addTearDown(db.close);

    // Derived data, so creating it empty is correct — it rebuilds on demand.
    expect(await db.select(db.occurrenceRollups).get(), isEmpty);

    await db.into(db.occurrenceRollups).insert(
          OccurrenceRollupsCompanion.insert(
            commitmentId: 'c1',
            scope: PeriodScope.daily,
            spanStart: d(2026, 8, 1),
            spanEnd: d(2026, 8, 1),
            status: OccurrenceStatus.done,
            completed: 1,
            target: 1,
            credit: 1,
          ),
        );
    expect(await db.select(db.occurrenceRollups).get(), hasLength(1));
  });

  test('foreign keys are enforced after migrating, not just on fresh installs',
      () async {
    final db = _openMigratedFromV1();
    addTearDown(db.close);

    // beforeOpen sets PRAGMA foreign_keys per connection; a migrated database
    // must get it too, or cascade deletes silently stop working.
    await (db.delete(db.commitments)..where((t) => t.id.equals('c1'))).go();
    expect(await db.select(db.trackingEvents).get(), isEmpty);
    expect(await db.select(db.pausePeriods).get(), isEmpty);
  });

  test('a fresh v2 install still works and reports version 2', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await TrackingRepository(db).createCommitment(
      name: 'Fresh',
      frequency: const Frequency.daily(),
      startedOn: d(2026, 8, 1),
      nowUtc: DateTime.utc(2026, 8, 28),
    );
    expect(await _userVersion(db), 2);
    expect((await TrackingRepository(db).readAll()).commitments, hasLength(1));
  });

}
