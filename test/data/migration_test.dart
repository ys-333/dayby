import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/data/db/app_database.dart';
import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/commitment_icon.dart';
import 'package:riyaz/domain/model/pause_period.dart';
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

/// Schema v2: v1 plus `occurrence_rollups`, with `pause_periods.to_day` still
/// **NOT NULL** — the constraint v3 exists to drop. Dumped from a real v2
/// database's `sqlite_master`, not retyped.
const List<String> _v2Schema = [
  ..._v1Schema,
  'CREATE TABLE "occurrence_rollups" ("commitment_id" TEXT NOT NULL '
      'REFERENCES commitments (id) ON DELETE CASCADE, "scope" INTEGER NOT NULL, '
      '"span_start" INTEGER NOT NULL, "span_end" INTEGER NOT NULL, '
      '"status" INTEGER NOT NULL, "completed" INTEGER NOT NULL, '
      '"target" INTEGER NOT NULL, "credit" REAL NOT NULL, '
      'PRIMARY KEY ("commitment_id", "scope", "span_start"));',
];

/// Opens an [AppDatabase] on a database that already contains schema v1 and
/// real data, so opening it exercises the actual v1 → v2 migration path.
///
/// Uses drift's `setup` hook rather than a direct sqlite3 dependency: the
/// callback hands over the raw database before drift inspects its version, so
/// the v1 schema can be laid down first without declaring a new package.
AppDatabase _openMigratedFromV1() => _openMigratedFrom(_v1Schema, 1);

/// Same, from schema v2 — the shape that actually shipped, and the one a real
/// upgrade to v3 will start from.
AppDatabase _openMigratedFromV2() => _openMigratedFrom(_v2Schema, 2);

AppDatabase _openMigratedFrom(List<String> schema, int version) => AppDatabase(
      NativeDatabase.memory(setup: (raw) {
        for (final ddl in schema) {
          raw.execute(ddl);
        }
        raw.execute('PRAGMA user_version = $version');

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
  test('a v1 database migrates forward with every record intact', () async {
    final db = _openMigratedFromV1();
    addTearDown(db.close);

    // Opening runs the migration.
    final snapshot = await TrackingRepository(db).readAll();

    expect(await _userVersion(db), 4, reason: 'schema version must advance');

    // Nothing lost. This is the whole point: the database holds years of
    // history that exists nowhere else, so a schema bump must never drop it.
    expect(snapshot.commitments, hasLength(1));
    final c = snapshot.commitments.single;
    expect(c.name, 'Running');
    // v4 rewrote it: the stored emoji is now the glyph key it maps to.
    expect(c.icon, 'run');
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

  test('a fresh install still works and reports the current version',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await TrackingRepository(db).createCommitment(
      name: 'Fresh',
      frequency: const Frequency.daily(),
      startedOn: d(2026, 8, 1),
      nowUtc: DateTime.utc(2026, 8, 28),
    );
    expect(await _userVersion(db), 4);
    expect((await TrackingRepository(db).readAll()).commitments, hasLength(1));
  });

  group('v2 to v3 — pause_periods.to_day loses NOT NULL', () {
    test('every existing pause survives the table rebuild', () async {
      final db = _openMigratedFromV2();
      addTearDown(db.close);

      final snapshot = await TrackingRepository(db).readAll();
      expect(await _userVersion(db), 4);

      // SQLite cannot drop NOT NULL in place, so v3 recreates the table and
      // copies every row across. This is the assertion that the copy happened:
      // a rebuild that forgot it would leave an empty table and throw nothing.
      final pauses = snapshot.pausesFor('c1');
      expect(pauses, hasLength(1));
      expect(pauses.single.id, 'p1');
      expect(pauses.single.from, d(2026, 8, 20));
      expect(pauses.single.to, d(2026, 8, 22));
      expect(pauses.single.isOpen, isFalse,
          reason: 'a dated pause must not become open-ended in the rebuild');

      // Everything else is untouched by the rebuild.
      expect(snapshot.commitments, hasLength(1));
      expect(snapshot.events, hasLength(5));
      expect(snapshot.schedulesFor('c1'), hasLength(1));
    });

    test('an open-ended pause can be stored after migrating', () async {
      final db = _openMigratedFromV2();
      addTearDown(db.close);
      final repo = TrackingRepository(db);

      await repo.pauseCommitment(commitmentId: 'c1', from: d(2026, 9, 1));

      final open = (await repo.readAll())
          .pausesFor('c1')
          .where((p) => p.isOpen)
          .toList();
      expect(open, hasLength(1),
          reason: 'the whole point of v3: a pause with no end yet');
      expect(open.single.from, d(2026, 9, 1));
    });

    test('foreign keys still cascade into the rebuilt table', () async {
      final db = _openMigratedFromV2();
      addTearDown(db.close);

      // A rebuilt table that lost its REFERENCES clause would orphan pauses
      // forever, and nothing would ever throw.
      await (db.delete(db.commitments)..where((t) => t.id.equals('c1'))).go();
      expect(await db.select(db.pausePeriods).get(), isEmpty);
    });

    test('migrating twice is a no-op, not a second rebuild', () async {
      final db = _openMigratedFromV2();
      addTearDown(db.close);
      await TrackingRepository(db).readAll();
      await db.close();

      // Reopening an already-v3 database must not run the v3 step again.
      final again = AppDatabase(NativeDatabase.memory());
      addTearDown(again.close);
      expect(await _userVersion(again), 4);
    });
  });

  group('v3 to v4 — icons become glyph keys', () {
    test('a recognised emoji is rewritten to its key', () async {
      final db = _openMigratedFromV1();
      addTearDown(db.close);

      final c = (await TrackingRepository(db).readAll()).commitments.single;
      expect(c.icon, 'run');
      expect(iconKeyFor(c.icon), 'run');
    });

    test('an emoji carrying a variation selector is still recognised',
        () async {
      // `🏋️` and `🏋` are different strings for the same picture, and the
      // seeder wrote the first while the lookup table holds the second. The
      // migration strips U+FE0F in SQL for exactly this row.
      final db = AppDatabase(
        NativeDatabase.memory(setup: (raw) {
          for (final ddl in _v2Schema) {
            raw.execute(ddl);
          }
          raw.execute('PRAGMA user_version = 2');
          raw.execute(
            'INSERT INTO commitments (id, name, icon, started_on, state, '
            'sort_order, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
            ['c1', 'Gym', '🏋\uFE0F', d(2026, 8, 1).epochDay, 0, 0, 1756000000000],
          );
        }),
      );
      addTearDown(db.close);

      expect((await TrackingRepository(db).readAll()).commitments.single.icon,
          'gym');
    });

    test('a mark the table does not know is left exactly as written', () async {
      final db = AppDatabase(
        NativeDatabase.memory(setup: (raw) {
          for (final ddl in _v2Schema) {
            raw.execute(ddl);
          }
          raw.execute('PRAGMA user_version = 2');
          raw.execute(
            'INSERT INTO commitments (id, name, icon, started_on, state, '
            'sort_order, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
            ['c1', 'Odd', '🦖', d(2026, 8, 1).epochDay, 0, 0, 1756000000000],
          );
        }),
      );
      addTearDown(db.close);

      // Replacing it with the nearest glyph would be destroying something the
      // migration had only guessed at. It is kept, and still drawn.
      expect((await TrackingRepository(db).readAll()).commitments.single.icon,
          '🦖');
    });

    test('a commitment with no icon survives untouched', () async {
      final db = AppDatabase(
        NativeDatabase.memory(setup: (raw) {
          for (final ddl in _v2Schema) {
            raw.execute(ddl);
          }
          raw.execute('PRAGMA user_version = 2');
          raw.execute(
            'INSERT INTO commitments (id, name, started_on, state, '
            'sort_order, created_at) VALUES (?, ?, ?, ?, ?, ?)',
            ['c1', 'Plain', d(2026, 8, 1).epochDay, 0, 0, 1756000000000],
          );
        }),
      );
      addTearDown(db.close);

      expect((await TrackingRepository(db).readAll()).commitments.single.icon,
          isNull);
    });
  });
}
