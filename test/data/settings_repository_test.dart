import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/settings.dart';
import 'package:riyaz/data/db/app_database.dart';
import 'package:riyaz/data/repository/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SettingsRepository(db);
  });

  tearDown(() => db.close());

  /// Writes a raw string past the repository, the way a hand-repaired backup or
  /// an older build would have left it.
  Future<void> putRaw(String key, String value) =>
      db.into(db.settings).insertOnConflictUpdate(
            SettingsCompanion.insert(key: key, value: value),
          );

  group('defaults', () {
    test('an empty database yields the compiled defaults', () async {
      final loaded = await repo.load();
      const defaults = AppSettings();

      expect(loaded.timezoneName, defaults.timezoneName);
      expect(loaded.dayBoundaryHour, defaults.dayBoundaryHour);
      expect(loaded.weekStartsOn, defaults.weekStartsOn);
    });

    test('a fresh install writes nothing — load does not seed rows', () async {
      await repo.load();
      final rows = await db.select(db.settings).get();
      expect(rows, isEmpty,
          reason: 'load() must be a pure read; seeding on read would make a '
              'first launch a write and defeat the absent-key fallback');
    });
  });

  group('round trip', () {
    test('every field survives a save and reload', () async {
      await repo.save(const AppSettings(
        timezoneName: 'Europe/Berlin',
        dayBoundaryHour: 2,
        weekStartsOn: DateTime.sunday,
      ));

      final loaded = await repo.load();
      expect(loaded.timezoneName, 'Europe/Berlin');
      expect(loaded.dayBoundaryHour, 2);
      expect(loaded.weekStartsOn, DateTime.sunday);
    });

    test('saving twice overwrites rather than duplicating', () async {
      await repo.save(const AppSettings(dayBoundaryHour: 2));
      await repo.save(const AppSettings(dayBoundaryHour: 6));

      final loaded = await repo.load();
      expect(loaded.dayBoundaryHour, 6);

      final rows = await (db.select(db.settings)
            ..where((t) => t.key.equals(SettingsRepository.dayBoundaryKey)))
          .get();
      expect(rows, hasLength(1));
    });

    test('a boundary of 0 is stored, not mistaken for absent', () async {
      // Midnight is a legitimate choice and it is also the falsy value in every
      // language this could have been written in. Worth pinning.
      await repo.save(const AppSettings(dayBoundaryHour: 0));
      expect((await repo.load()).dayBoundaryHour, 0);
    });
  });

  group('a malformed row must not stop the app opening', () {
    test('an unparseable boundary falls back to the default', () async {
      await putRaw(SettingsRepository.dayBoundaryKey, 'four');
      expect((await repo.load()).dayBoundaryHour, const AppSettings().dayBoundaryHour);
    });

    test('an out-of-range boundary falls back rather than being stored',
        () async {
      // 25 would not throw. It would silently mis-date every record in the
      // database, which is the failure this project ranks above all others.
      await putRaw(SettingsRepository.dayBoundaryKey, '25');
      expect((await repo.load()).dayBoundaryHour, const AppSettings().dayBoundaryHour);

      await putRaw(SettingsRepository.dayBoundaryKey, '-1');
      expect((await repo.load()).dayBoundaryHour, const AppSettings().dayBoundaryHour);
    });

    test('an out-of-range week start falls back', () async {
      await putRaw(SettingsRepository.weekStartKey, '9');
      expect((await repo.load()).weekStartsOn, const AppSettings().weekStartsOn);
    });

    test('a malformed row is left in place, not corrected', () async {
      await putRaw(SettingsRepository.dayBoundaryKey, 'four');
      await repo.load();

      final row = await (db.select(db.settings)
            ..where((t) => t.key.equals(SettingsRepository.dayBoundaryKey)))
          .getSingle();
      expect(row.value, 'four',
          reason: 'rewriting a value we only guessed at would destroy whatever '
              'the user actually meant');
    });

    test('one bad field does not drag down the others', () async {
      await putRaw(SettingsRepository.dayBoundaryKey, 'nonsense');
      await putRaw(SettingsRepository.timezoneKey, 'Europe/Berlin');

      final loaded = await repo.load();
      expect(loaded.dayBoundaryHour, const AppSettings().dayBoundaryHour);
      expect(loaded.timezoneName, 'Europe/Berlin');
    });
  });

  test('it reads only its own keys, and disturbs no one else\'s', () async {
    // The table is shared: ReviewRepository and RollupRepository have used it
    // since schema v1. A settings write must not touch their rows.
    await putRaw('review.lastSeenWeek', '20330');
    await putRaw('rollup.logicVersion', 'v7');

    await repo.save(const AppSettings(dayBoundaryHour: 5));

    final review = await (db.select(db.settings)
          ..where((t) => t.key.equals('review.lastSeenWeek')))
        .getSingle();
    final rollup = await (db.select(db.settings)
          ..where((t) => t.key.equals('rollup.logicVersion')))
        .getSingle();

    expect(review.value, '20330');
    expect(rollup.value, 'v7');
  });
}
