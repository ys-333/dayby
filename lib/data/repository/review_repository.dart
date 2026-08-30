import 'package:drift/drift.dart';
import 'package:riyaz/domain/time/civil_date.dart';

import '../db/app_database.dart';

/// Remembers which closed week the user has already been shown.
///
/// One row in the settings table rather than a column anywhere: it is a piece
/// of UI state, not history, and the schema is for things a lost phone must
/// not lose. Storing it in the database rather than shared preferences keeps
/// the promise that a backup of the database is a complete backup — restore
/// onto a new phone and last Monday's review does not reappear.
///
/// The value is the **week's start date**, not a boolean. A flag would say
/// "a review was dismissed" and could never say *which*, so the first Monday
/// after a restore would either re-show a week the user had already read or
/// silently swallow one they had not.
class ReviewRepository {
  ReviewRepository(this._db);

  static const String _key = 'review.lastSeenWeek';

  final AppDatabase _db;

  /// The most recent week the user has closed out, or null if they never have.
  Future<CivilDate?> lastSeenWeek() async {
    final row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(_key)))
        .getSingleOrNull();
    final raw = row?.value;
    if (raw == null) return null;
    final epochDay = int.tryParse(raw);
    // A settings row is a string and a hand-repaired backup can put anything
    // in it. An unparseable value means "never seen" rather than a crash on
    // the tracking screen.
    return epochDay == null ? null : CivilDate.fromEpochDay(epochDay);
  }

  /// Live, so dismissing the review makes the card go away without the screen
  /// having to know it should re-read anything.
  Stream<CivilDate?> watchLastSeenWeek() async* {
    yield await lastSeenWeek();
    yield* _db
        .tableUpdates(TableUpdateQuery.onTable(_db.settings))
        .asyncMap((_) => lastSeenWeek());
  }

  Future<void> markSeen(CivilDate weekStart) =>
      _db.into(_db.settings).insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: _key,
              value: '${weekStart.epochDay}',
            ),
          );
}
