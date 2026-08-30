import 'package:drift/drift.dart';
import 'package:riyaz/app/settings.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/domain/time/clock.dart';

import '../db/app_database.dart';
import '../db/mappers.dart';
import '../repository/rollup_repository.dart';
import '../repository/tracking_repository.dart';
import 'backup_codec.dart';
import 'backup_document.dart';

/// How an import treats what is already there.
enum ImportMode {
  /// Wipe first. The restoring-a-lost-phone case.
  replace,

  /// Keep existing records; add only ids not already present. Re-importing the
  /// same file twice changes nothing, which makes the operation safe to retry.
  merge,
}

class ImportResult {
  const ImportResult({
    required this.inserted,
    required this.skipped,
    required this.dropped,
    required this.mode,
  });

  final int inserted;

  /// Records whose id already existed, in [ImportMode.merge].
  final int skipped;

  /// Orphans discarded because their commitment was not in the file.
  final int dropped;

  final ImportMode mode;
}

class BackupService {
  const BackupService({
    required this.database,
    required this.repository,
    required this.rollups,
    required this.clock,
    required this.settings,
    this.codec = const BackupCodec(),
  });

  final AppDatabase database;
  final TrackingRepository repository;
  final RollupRepository rollups;
  final Clock clock;
  final AppSettings settings;
  final BackupCodec codec;

  // ------------------------------------------------------------------ export

  Future<BackupDocument> buildDocument() async {
    final snapshot = await repository.readAll();
    return BackupDocument(
      version: BackupDocument.currentVersion,
      exportedAt: clock.nowUtc(),
      timezoneName: settings.timezoneName,
      dayBoundaryHour: settings.dayBoundaryHour,
      weekStartsOn: settings.weekStartsOn,
      commitments: snapshot.commitments,
      schedules: [
        for (final list in snapshot.schedules.values) ...list,
      ],
      pauses: [
        for (final list in snapshot.pauses.values) ...list,
      ],
      events: snapshot.events,
    );
  }

  Future<String> exportJson() async => codec.encode(await buildDocument());

  /// A filename that sorts chronologically and says what it is.
  String suggestedFileName(CivilDate today) => 'riyaz-backup-${today.iso}.json';

  // ------------------------------------------------------------------ import

  /// Parses, structurally validates, and reports what would happen — without
  /// touching the database. The user sees this before anything is written.
  BackupPreview validate(String json) {
    final doc = codec.decode(json);
    final warnings = <String>[];

    final ids = {for (final c in doc.commitments) c.id};

    final orphanSchedules =
        doc.schedules.where((s) => !ids.contains(s.commitmentId)).length;
    final orphanEvents =
        doc.events.where((e) => !ids.contains(e.commitmentId)).length;
    final orphanPauses =
        doc.pauses.where((p) => !ids.contains(p.commitmentId)).length;

    if (orphanSchedules + orphanEvents + orphanPauses > 0) {
      warnings.add(
        '${orphanSchedules + orphanEvents + orphanPauses} records reference a '
        'commitment that is not in this file and will be skipped.',
      );
    }

    final scheduled = {for (final s in doc.schedules) s.commitmentId};
    final unscheduled =
        doc.commitments.where((c) => !scheduled.contains(c.id)).length;
    if (unscheduled > 0) {
      warnings.add(
        '$unscheduled commitments have no schedule and will never expect '
        'anything until one is added.',
      );
    }

    if (doc.timezoneName != settings.timezoneName) {
      warnings.add(
        'This backup was written in ${doc.timezoneName}; this device is set to '
        '${settings.timezoneName}. Day boundaries may shift.',
      );
    }
    if (doc.dayBoundaryHour != settings.dayBoundaryHour) {
      warnings.add(
        'Day boundary differs: backup ${doc.dayBoundaryHour}:00, device '
        '${settings.dayBoundaryHour}:00.',
      );
    }

    return BackupPreview(document: doc, warnings: warnings);
  }

  /// Applies a validated document.
  ///
  /// Everything happens in one transaction: a restore that fails halfway would
  /// leave a history that is neither the old one nor the new one, which for
  /// this app is the worst possible outcome.
  Future<ImportResult> import(
    BackupDocument doc, {
    ImportMode mode = ImportMode.merge,
  }) async {
    final ids = {for (final c in doc.commitments) c.id};
    bool known(String commitmentId) => ids.contains(commitmentId);

    final schedules = doc.schedules.where((s) => known(s.commitmentId)).toList();
    final pauses = doc.pauses.where((p) => known(p.commitmentId)).toList();
    final events = doc.events.where((e) => known(e.commitmentId)).toList();
    final dropped = (doc.schedules.length - schedules.length) +
        (doc.pauses.length - pauses.length) +
        (doc.events.length - events.length);

    var inserted = 0;
    var skipped = 0;

    await database.transaction(() async {
      if (mode == ImportMode.replace) {
        // Commitments cascade to everything else.
        await database.delete(database.commitments).go();
        await database.delete(database.occurrenceRollups).go();
      }

      final existingCommitments = mode == ImportMode.merge
          ? {
              for (final c in await database.select(database.commitments).get())
                c.id,
            }
          : <String>{};
      final existingEvents = mode == ImportMode.merge
          ? {
              for (final e
                  in await database.select(database.trackingEvents).get())
                e.id,
            }
          : <String>{};
      final existingSchedules = mode == ImportMode.merge
          ? {
              for (final s
                  in await database.select(database.commitmentSchedules).get())
                s.id,
            }
          : <String>{};
      final existingPauses = mode == ImportMode.merge
          ? {
              for (final p
                  in await database.select(database.pausePeriods).get())
                p.id,
            }
          : <String>{};

      var order = existingCommitments.length;
      for (final c in doc.commitments) {
        if (existingCommitments.contains(c.id)) {
          skipped++;
          continue;
        }
        await database.into(database.commitments).insert(
              CommitmentsCompanion.insert(
                id: c.id,
                name: c.name,
                startedOn: c.startedOn,
                state: c.state,
                createdAt: doc.exportedAt,
                icon: Value(c.icon),
                description: Value(c.description),
                categoryId: Value(c.categoryId),
                archivedOn: Value(c.archivedOn),
                sortOrder: Value(order++),
              ),
            );
        inserted++;
      }

      for (final s in schedules) {
        if (existingSchedules.contains(s.id)) {
          skipped++;
          continue;
        }
        final columns = frequencyToColumns(s.frequency);
        await database.into(database.commitmentSchedules).insert(
              CommitmentSchedulesCompanion.insert(
                id: s.id,
                commitmentId: s.commitmentId,
                effectiveFrom: s.effectiveFrom,
                effectiveTo: Value(s.effectiveTo),
                frequencyType: columns.type,
                target: Value(columns.target),
                daysOfWeekMask: Value(columns.daysMask),
                everyNDays: Value(columns.everyN),
                targetMinutes: Value(s.targetMinutes),
              ),
            );
        inserted++;
      }

      for (final p in pauses) {
        if (existingPauses.contains(p.id)) {
          skipped++;
          continue;
        }
        await database.into(database.pausePeriods).insert(
              PausePeriodsCompanion.insert(
                id: p.id,
                commitmentId: p.commitmentId,
                fromDay: p.from,
                toDay: Value(p.to),
              ),
            );
        inserted++;
      }

      for (final e in events) {
        if (existingEvents.contains(e.id)) {
          skipped++;
          continue;
        }
        await database.into(database.trackingEvents).insert(
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
        inserted++;
      }
    });

    // Every derived number is now suspect. Invalidate from the earliest date
    // the import could have touched.
    final earliest = _earliestDate(doc);
    if (earliest != null) await rollups.markStale(earliest);

    return ImportResult(
      inserted: inserted,
      skipped: skipped,
      dropped: dropped,
      mode: mode,
    );
  }

  CivilDate? _earliestDate(BackupDocument doc) {
    CivilDate? earliest;
    void consider(CivilDate d) {
      if (earliest == null || d < earliest!) earliest = d;
    }

    for (final c in doc.commitments) {
      consider(c.startedOn);
    }
    for (final e in doc.events) {
      consider(e.accountingDate);
    }
    return earliest;
  }
}
