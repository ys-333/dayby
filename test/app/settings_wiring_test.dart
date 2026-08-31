import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/app/settings.dart';
import 'package:riyaz/data/db/app_database.dart';
import 'package:riyaz/data/repository/settings_repository.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// Phase 0's real claim is not that settings can be stored — it is that they
/// reach the accounting engine *synchronously*, and that changing one is
/// durable. A repository test cannot show either.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// A container wired the way `main()` wires the app: the database injected,
  /// and the settings seeded from one read taken before the first frame.
  Future<ProviderContainer> boot() async {
    final settings = await SettingsRepository(db).load();
    return ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialAppSettingsProvider.overrideWithValue(settings),
      ],
    );
  }

  test('stored settings reach the accounting calendar', () async {
    await SettingsRepository(db).save(const AppSettings(
      timezoneName: 'Europe/Berlin',
      dayBoundaryHour: 2,
      weekStartsOn: DateTime.sunday,
    ));

    final container = await boot();
    addTearDown(container.dispose);

    final calendar = container.read(accountingCalendarProvider);
    expect(calendar.zone.name, 'Europe/Berlin');
    expect(calendar.dayBoundaryHour, 2);
    expect(calendar.weekStartsOn, DateTime.sunday);
  });

  test('the settings provider is synchronous, not a Future', () async {
    final container = await boot();
    addTearDown(container.dispose);

    // Reading these must not require an await. If this ever stops compiling as
    // a plain read, the whole engine graph has gone async and every screen and
    // widget test goes with it — which is the trap §3 of the spec exists to
    // avoid.
    final AppSettings settings = container.read(appSettingsControllerProvider);
    final calendar = container.read(accountingCalendarProvider);

    expect(settings, isA<AppSettings>());
    expect(calendar.dayBoundaryHour, settings.dayBoundaryHour);
  });

  test('a change propagates to the accounting calendar immediately', () async {
    final container = await boot();
    addTearDown(container.dispose);

    expect(container.read(accountingCalendarProvider).dayBoundaryHour, 4);

    await container
        .read(appSettingsControllerProvider.notifier)
        .update(const AppSettings(dayBoundaryHour: 6));

    expect(
      container.read(accountingCalendarProvider).dayBoundaryHour,
      6,
      reason: 'the calendar watches the settings; a write that does not rebuild '
          'it would leave the app dating records against the old boundary',
    );
  });

  test('a change survives a restart', () async {
    final first = await boot();
    await first
        .read(appSettingsControllerProvider.notifier)
        .update(const AppSettings(
          timezoneName: 'Europe/Berlin',
          dayBoundaryHour: 3,
          weekStartsOn: DateTime.sunday,
        ));
    first.dispose();

    // Same database, brand new container — the app being killed and reopened.
    final second = await boot();
    addTearDown(second.dispose);

    final settings = second.read(appSettingsControllerProvider);
    expect(settings.timezoneName, 'Europe/Berlin');
    expect(settings.dayBoundaryHour, 3);
    expect(settings.weekStartsOn, DateTime.sunday);
    expect(second.read(accountingCalendarProvider).zone.name, 'Europe/Berlin');
  });

  test('the write is persisted, not just held in memory', () async {
    final container = await boot();
    addTearDown(container.dispose);

    await container
        .read(appSettingsControllerProvider.notifier)
        .update(const AppSettings(dayBoundaryHour: 5));

    // Read past the provider entirely.
    final stored = await SettingsRepository(db).load();
    expect(stored.dayBoundaryHour, 5);
  });

  test('a fresh install boots on the defaults', () async {
    final container = await boot();
    addTearDown(container.dispose);

    const defaults = AppSettings();
    final settings = container.read(appSettingsControllerProvider);
    expect(settings.dayBoundaryHour, defaults.dayBoundaryHour);
    expect(settings.timezoneName, defaults.timezoneName);
  });
}
