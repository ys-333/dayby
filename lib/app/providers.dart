import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riyaz/data/db/app_database.dart';
import 'package:riyaz/data/db/connection.dart';
import 'package:riyaz/data/repository/rollup_repository.dart';
import 'package:riyaz/data/repository/settings_repository.dart';
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

/// What the app started with — the row values `main()` read from the database
/// before the first frame, or the compiled defaults on a fresh install.
///
/// Overridden in `main()` rather than loaded here, and that is the whole trick:
/// `accountingCalendarProvider` watches the settings and the entire engine graph
/// watches *that*, so a `Future`-returning settings provider would turn every
/// downstream provider async and ripple into every screen and every widget test.
/// Reading the database once, ahead of `runApp`, keeps all of it synchronous.
///
/// Tests that do not care about persistence get the defaults for free.
@Riverpod(keepAlive: true)
AppSettings initialAppSettings(Ref ref) => const AppSettings();

@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) =>
    SettingsRepository(ref.watch(appDatabaseProvider));

/// The live settings, and the only way to change them.
///
/// Persists first and updates state second, so a failed write leaves the app
/// showing what is actually stored rather than a value that survives only until
/// the next restart.
@Riverpod(keepAlive: true)
class AppSettingsController extends _$AppSettingsController {
  @override
  AppSettings build() => ref.watch(initialAppSettingsProvider);

  Future<void> update(AppSettings next) async {
    await ref.read(settingsRepositoryProvider).save(next);
    state = next;
  }
}

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
  final settings = ref.watch(appSettingsControllerProvider);
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
