import 'package:drift/drift.dart';
// Imported for the generated part file, which references these types in the
// signatures produced by the table type converters and enum columns.
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/time/accounting_calendar.dart';
import 'package:riyaz/domain/time/civil_date.dart';

import 'converters.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Commitments,
    CommitmentSchedules,
    TrackingEvents,
    PausePeriods,
    Settings,
    OccurrenceRollups,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // Every bump adds an explicit step. `deleteOnSchemaChange` is never
          // acceptable here: the database holds years of behavioural history
          // that exists nowhere else, and wiping it on a schema bump would
          // destroy the product.
          if (from < 2) {
            // v2 adds materialised rollups. Purely derived, so creating the
            // table empty is safe — it rebuilds itself on first read.
            await m.createTable(occurrenceRollups);
          }
        },
        beforeOpen: (details) async {
          // Cascade deletes are declared on the tables; SQLite ignores them
          // unless foreign keys are switched on per connection.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
