import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/data/db/app_database.dart';
import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/features/settings/backup_controller.dart';
import 'package:riyaz/app/resolution.dart';
import 'package:riyaz/app/settings.dart';
import 'package:riyaz/data/backup/backup_service.dart';
import 'package:riyaz/data/repository/rollup_repository.dart';
import 'package:riyaz/domain/accounting/accounting_engine.dart';
import 'package:riyaz/domain/recurrence/recurrence_engine.dart';
import 'package:riyaz/domain/time/accounting_calendar.dart';
import 'package:riyaz/domain/time/clock.dart';
import 'package:timezone/timezone.dart' as tz;

/// Shared widget-test harness: a real in-memory database plus a frozen clock,
/// so every screen test exercises the genuine engine graph rather than mocks.
class Harness {
  Harness({String at = '2026-08-28T10:00:00+05:30'})
      : clock = FixedClock.iso(at),
        db = AppDatabase(NativeDatabase.memory()) {
    repo = TrackingRepository(db);
  }

  final FixedClock clock;
  final AppDatabase db;
  late final TrackingRepository repo;

  DateTime get nowUtc => clock.nowUtc();

  /// Files written by the screen under test, path to contents.
  ///
  /// In-memory rather than real: `testWidgets` runs in a fake-async zone where
  /// real file I/O never completes, so a screen that writes to disk during a
  /// `pumpAndSettle` hangs indefinitely. The real store is exercised by its own
  /// unit test, where the event loop is real.
  final Map<String, String> writtenFiles = {};

  /// Pumps [child] against this harness's database and frozen clock, with
  /// file writes captured in [writtenFiles].
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(clock),
          backupFileStoreProvider
              .overrideWithValue(_InMemoryFileStore(writtenFiles)),
        ],
        child: MaterialApp(home: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Exports through the same service the UI uses.
  Future<String> backupJson() {
    final calendar = AccountingCalendar(zone: tz.getLocation('Asia/Kolkata'));
    return BackupService(
      database: db,
      repository: repo,
      rollups: RollupRepository(
        db,
        ResolutionService(
          repository: repo,
          accounting: AccountingEngine(
            calendar: calendar,
            recurrence: RecurrenceEngine(calendar),
          ),
          clock: clock,
        ),
      ),
      clock: clock,
      settings: const AppSettings(),
    ).exportJson();
  }

  /// Simulates a lost device.
  Future<void> wipe() async {
    await db.delete(db.commitments).go();
    await db.delete(db.occurrenceRollups).go();
  }

  Future<void> dispose() => db.close();
}

class _InMemoryFileStore implements BackupFileStore {
  _InMemoryFileStore(this.files);

  final Map<String, String> files;

  @override
  Future<String> write(String contents, String fileName) async {
    final path = '/test/$fileName';
    files[path] = contents;
    return path;
  }

  @override
  Future<List<String>> listExports() async =>
      files.keys.toList()..sort((a, b) => b.compareTo(a));

  @override
  Future<String> read(String path) async => files[path]!;
}
