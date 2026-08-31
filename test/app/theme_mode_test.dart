import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/app/settings.dart';
import 'package:riyaz/app/theme_preference.dart';
import 'package:riyaz/data/db/app_database.dart';
import 'package:riyaz/data/repository/settings_repository.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('the stored vocabulary', () {
    test('every mode round-trips through encode and decode', () {
      for (final mode in ThemePreference.choices) {
        expect(ThemePreference.decode(ThemePreference.encode(mode)), mode);
      }
    });

    test('all three modes are offered, not just light and dark', () {
      // Dropping "system" would be a downgrade for anyone whose phone already
      // changes theme on a schedule.
      expect(ThemePreference.choices, hasLength(3));
      expect(ThemePreference.choices, contains(ThemeMode.system));
    });

    test('an unset or unreadable value follows the system', () {
      expect(ThemePreference.decode(null), ThemeMode.system);
      expect(ThemePreference.decode(''), ThemeMode.system);
      expect(ThemePreference.decode('midnight'), ThemeMode.system);
      // This is read on the startup path, so a hand-edited row must not throw
      // before the first frame.
    });
  });

  group('persistence', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<ProviderContainer> boot() async {
      final repo = SettingsRepository(db);
      final settings = await repo.load();
      final theme = ThemePreference.decode(
        await repo.readRaw(ThemePreference.key),
      );
      return ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          initialAppSettingsProvider.overrideWithValue(settings),
          initialThemeModeProvider.overrideWithValue(theme),
        ],
      );
    }

    test('a fresh install follows the system', () async {
      final container = await boot();
      addTearDown(container.dispose);
      expect(container.read(themeModeControllerProvider), ThemeMode.system);
    });

    test('a choice takes effect immediately', () async {
      final container = await boot();
      addTearDown(container.dispose);

      await container
          .read(themeModeControllerProvider.notifier)
          .select(ThemeMode.dark);

      expect(container.read(themeModeControllerProvider), ThemeMode.dark);
    });

    test('a choice survives a restart', () async {
      final first = await boot();
      await first
          .read(themeModeControllerProvider.notifier)
          .select(ThemeMode.dark);
      first.dispose();

      // Same database, new container — the app killed and reopened.
      final second = await boot();
      addTearDown(second.dispose);
      expect(second.read(themeModeControllerProvider), ThemeMode.dark);
    });

    test('switching back to system is itself persisted', () async {
      final first = await boot();
      await first
          .read(themeModeControllerProvider.notifier)
          .select(ThemeMode.light);
      await first
          .read(themeModeControllerProvider.notifier)
          .select(ThemeMode.system);
      first.dispose();

      final second = await boot();
      addTearDown(second.dispose);
      // "System" must be a stored choice, not the absence of one — otherwise
      // returning to it would be indistinguishable from never having chosen,
      // which is fine here but would not be if the default ever changed.
      expect(second.read(themeModeControllerProvider), ThemeMode.system);
      expect(
        await SettingsRepository(db).readRaw(ThemePreference.key),
        'system',
      );
    });

    test('the theme does not touch the accounting settings', () async {
      // Theme is not an interpretation setting: it must never end up in
      // AppSettings, which travels inside every backup.
      final container = await boot();
      addTearDown(container.dispose);

      await container
          .read(themeModeControllerProvider.notifier)
          .select(ThemeMode.dark);

      final settings = await SettingsRepository(db).load();
      expect(settings.dayBoundaryHour, 4);
      expect(settings.timezoneName, const AppSettings().timezoneName);
    });
  });
}
