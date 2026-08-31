import 'package:riyaz/app/settings.dart';
import 'package:riyaz/data/db/app_database.dart';

/// Reads and writes the user's [AppSettings] in the key-value `settings` table.
///
/// The table is not new — it has held `review.lastSeenWeek` and the rollup
/// watermarks since schema v1. What was missing was anything that stored the
/// *user's* preferences in it: [AppSettings] was a compile-time constant, so
/// the day boundary and timezone were unchangeable and the Settings screen
/// showed them as disabled rows.
///
/// Values are strings, and a hand-repaired backup can put anything in one. Every
/// read here therefore falls back to the compiled default rather than throwing —
/// the same stance `ReviewRepository` takes, and for the same reason: a
/// malformed row must not stop the app from opening. A malformed row is also
/// left in place rather than corrected, because rewriting a value we only
/// guessed at would destroy whatever the user actually meant.
class SettingsRepository {
  const SettingsRepository(this._db);

  static const String timezoneKey = 'settings.timezone';
  static const String dayBoundaryKey = 'settings.dayBoundaryHour';
  static const String weekStartKey = 'settings.weekStartsOn';

  final AppDatabase _db;

  /// Everything the app needs before its first frame.
  ///
  /// One query rather than three: this sits on the startup path, ahead of
  /// `runApp`, and three round trips to SQLite is three chances to be slow on a
  /// cold start.
  Future<AppSettings> load() async {
    final rows = await (_db.select(_db.settings)
          ..where((t) => t.key.isIn(const [
                timezoneKey,
                dayBoundaryKey,
                weekStartKey,
              ])))
        .get();

    final byKey = {for (final row in rows) row.key: row.value};
    const defaults = AppSettings();

    return AppSettings(
      timezoneName: byKey[timezoneKey] ?? defaults.timezoneName,
      dayBoundaryHour: _readInt(
        byKey[dayBoundaryKey],
        min: 0,
        max: 23,
        fallback: defaults.dayBoundaryHour,
      ),
      weekStartsOn: _readInt(
        byKey[weekStartKey],
        min: DateTime.monday,
        max: DateTime.sunday,
        fallback: defaults.weekStartsOn,
      ),
    );
  }

  /// Persists all three in one transaction.
  ///
  /// Atomic on purpose: the day boundary and the timezone are read together to
  /// interpret every stored date, and a half-applied write would leave the
  /// accounting calendar reading dates against a combination the user never
  /// chose.
  Future<void> save(AppSettings settings) => _db.transaction(() async {
        await _write(timezoneKey, settings.timezoneName);
        await _write(dayBoundaryKey, '${settings.dayBoundaryHour}');
        await _write(weekStartKey, '${settings.weekStartsOn}');
      });

  /// Reads one raw value, for a preference whose type belongs to a layer this
  /// one cannot import.
  ///
  /// `lib/data/` is Flutter-free and `ThemeMode` is a Flutter type, so the
  /// caller owns the vocabulary and the fallback. The reminder settings in
  /// Phase 5 will use the same pair.
  Future<String?> readRaw(String key) async {
    final row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> writeRaw(String key, String value) => _write(key, value);

  Future<void> _write(String key, String value) =>
      _db.into(_db.settings).insertOnConflictUpdate(
            SettingsCompanion.insert(key: key, value: value),
          );

  /// Parses a stored integer, rejecting anything outside [min]..[max].
  ///
  /// The range check is not defensive padding. A day boundary of 25 or a week
  /// starting on day 9 would not throw — it would silently produce wrong
  /// accounting for every date in the database, which is the one failure this
  /// project ranks above all others.
  static int _readInt(
    String? raw,
    {required int min,
    required int max,
    required int fallback}
  ) {
    if (raw == null) return fallback;
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < min || parsed > max) return fallback;
    return parsed;
  }
}
