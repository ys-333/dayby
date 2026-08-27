import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riyaz/data/db/app_database.dart';
import 'package:riyaz/data/db/connection.dart';
import 'package:riyaz/data/repository/rollup_repository.dart';
import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/data/system_clock.dart';
import 'package:riyaz/domain/accounting/accounting_engine.dart';
import 'package:riyaz/domain/analytics/analytics_engine.dart';
import 'package:riyaz/domain/recurrence/recurrence_engine.dart';
import 'package:riyaz/domain/time/accounting_calendar.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/domain/time/clock.dart';
import 'package:timezone/timezone.dart' as tz;

import 'resolution.dart';
import 'settings.dart';

part 'providers.g.dart';

/// Overridden in tests and at startup. Kept as a provider so the whole engine
/// graph can be driven from a [FixedClock] in a widget test.
@Riverpod(keepAlive: true)
Clock clock(Ref ref) => const SystemClock();

@Riverpod(keepAlive: true)
AppSettings appSettings(Ref ref) => const AppSettings();

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase(openConnection());
  ref.onDispose(db.close);
  return db;
}

@Riverpod(keepAlive: true)
TrackingRepository trackingRepository(Ref ref) =>
    TrackingRepository(ref.watch(appDatabaseProvider));

/// Rollups, wired to invalidate themselves on every write.
///
/// The callback is attached here rather than injected into the tracking
/// repository, because the rollup repository needs the resolution service,
/// which needs the tracking repository — the composition root is the only place
/// that can close the loop without a cycle.
@Riverpod(keepAlive: true)
RollupRepository rollupRepository(Ref ref) {
  final tracking = ref.watch(trackingRepositoryProvider);
  final rollups = RollupRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(resolutionServiceProvider),
  );
  tracking.onWrite = rollups.markStale;
  ref.onDispose(() => tracking.onWrite = null);
  return rollups;
}

@Riverpod(keepAlive: true)
AccountingCalendar accountingCalendar(Ref ref) {
  final settings = ref.watch(appSettingsProvider);
  return AccountingCalendar(
    zone: tz.getLocation(settings.timezoneName),
    dayBoundaryHour: settings.dayBoundaryHour,
    weekStartsOn: settings.weekStartsOn,
  );
}

@Riverpod(keepAlive: true)
RecurrenceEngine recurrenceEngine(Ref ref) =>
    RecurrenceEngine(ref.watch(accountingCalendarProvider));

@Riverpod(keepAlive: true)
AccountingEngine accountingEngine(Ref ref) => AccountingEngine(
      calendar: ref.watch(accountingCalendarProvider),
      recurrence: ref.watch(recurrenceEngineProvider),
    );

@Riverpod(keepAlive: true)
AnalyticsEngine analyticsEngine(Ref ref) => const AnalyticsEngine();

/// The accounting day currently in progress.
@riverpod
CivilDate today(Ref ref) => ref
    .watch(accountingCalendarProvider)
    .today(ref.watch(clockProvider));

@Riverpod(keepAlive: true)
ResolutionService resolutionService(Ref ref) => ResolutionService(
      repository: ref.watch(trackingRepositoryProvider),
      accounting: ref.watch(accountingEngineProvider),
      clock: ref.watch(clockProvider),
    );

/// Resolved history for an arbitrary range. Screens watch this rather than
/// re-running the engines themselves.
@riverpod
Stream<ResolvedHistory> resolvedHistory(Ref ref, CivilDateRange range) =>
    ref.watch(resolutionServiceProvider).watch(range);
