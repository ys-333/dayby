import 'package:drift/drift.dart';
import 'package:riyaz/app/resolution.dart';
import 'package:riyaz/domain/analytics/consistency_summary.dart';
import 'package:riyaz/domain/time/civil_date.dart';

import '../db/app_database.dart';

/// Reads and maintains the materialised rollup table.
///
/// Invalidation is a single watermark rather than per-row dirty tracking: any
/// write records the earliest date it could have affected, and the next read
/// rebuilds from there forward. Backfilling last March costs a rebuild of March
/// onward; ticking today costs almost nothing. Per-row tracking would be more
/// precise and considerably easier to get subtly wrong.
class RollupRepository {
  RollupRepository(this._db, this._resolution);

  static const String _staleKey = 'rollup.staleFrom';
  static const String _coveredKey = 'rollup.coveredTo';
  static const String _versionKey = 'rollup.logicVersion';

  /// Bump when resolution semantics change.
  ///
  /// The watermark tracks changed *data* and is blind to a changed *rule*. A
  /// rollup is a cached `AccountingEngine.resolve()` result, so it is only
  /// valid while the rules that produced it hold. Version 2 is the period-skip
  /// fix: before it, one skipped day marked a whole week skipped, and every
  /// rollup written under that rule went on contradicting the engine
  /// afterwards with nothing to notice.
  static const int _resolutionVersion = 2;

  final AppDatabase _db;
  final ResolutionService _resolution;

  /// Records that data on or after [from] changed.
  Future<void> markStale(CivilDate from) async {
    final current = await _readMarker(_staleKey);
    if (current != null && current <= from) return;
    await _writeMarker(_staleKey, from);
  }

  /// The contract these rollups were computed under.
  ///
  /// The weights are folded in rather than left to [_resolutionVersion] alone.
  /// [ScoringWeights] exists to be changed, and requiring whoever changes it to
  /// also remember a version bump is the kind of discipline that fails
  /// silently — which is exactly the failure this whole marker guards against.
  ///
  /// The calendar's three settings are folded in for the same reason, and they
  /// are the ones with teeth. **A rollup is a cached answer to "what happened
  /// on this date", and all three change what a date *is*.** Move the day
  /// boundary from 04:00 to midnight and every late-night completion shifts a
  /// day; change the timezone and the same instants land on different days;
  /// change the week start and every weekly target is scored over a different
  /// seven days. Every existing rollup would then disagree with the engine,
  /// permanently and silently, because the staleness watermark tracks changed
  /// *data* and none of the underlying rows would have moved.
  ///
  /// **Latent today, deliberately.** `appSettings` is a hardcoded constant with
  /// no runtime source, so nothing can change these yet. This is insurance for
  /// the day the timezone becomes device-derived or the boundary becomes a
  /// setting — and it is the cheap half of that change, so it goes in now
  /// rather than being remembered later.
  String get _logicVersion {
    final weights = _resolution.accounting.weights;
    final calendar = _resolution.accounting.calendar;
    return '$_resolutionVersion'
        '/${weights.done}/${weights.partial}'
        '/${calendar.zone.name}'
        '/${calendar.dayBoundaryHour}'
        '/${calendar.weekStartsOn}';
  }

  /// Discards the cache when it was built under rules that no longer apply.
  ///
  /// Everything, not a date range: a rule change invalidates every row at once,
  /// and there is no watermark that can express "all of it". Cheap, because a
  /// rollup is derived — the canonical records are untouched and it rebuilds
  /// from them on the next read.
  Future<void> _discardIfLogicChanged() async {
    final row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(_versionKey)))
        .getSingleOrNull();
    final current = _logicVersion;
    // A database written before this marker existed reports null, and its
    // rollups came from unknown rules. Treat that as a mismatch.
    if (row?.value == current) return;

    await _db.transaction(() async {
      await _db.delete(_db.occurrenceRollups).go();
      await _clearMarker(_staleKey);
      await _clearMarker(_coveredKey);
      await _db.into(_db.settings).insertOnConflictUpdate(
            SettingsCompanion.insert(key: _versionKey, value: current),
          );
    });
  }

  /// Brings rollups up to date for [range], rebuilding only what is stale.
  Future<void> ensureFresh(CivilDateRange range) async {
    await _discardIfLogicChanged();
    final stale = await _readMarker(_staleKey);
    final covered = await _readMarker(_coveredKey);

    // Nothing has ever been built, or the request reaches past what exists.
    final needsFullBuild = covered == null || range.end > covered;
    final rebuildFrom = switch ((stale, needsFullBuild)) {
      (null, false) => null,
      (null, true) => range.start,
      (final s?, false) => s,
      (final s?, true) => s < range.start ? s : range.start,
    };
    if (rebuildFrom == null) return;

    final from = rebuildFrom < range.start ? rebuildFrom : range.start;
    await _rebuild(CivilDateRange(from, range.end));

    await _clearMarker(_staleKey);
    final newCovered =
        covered == null || range.end > covered ? range.end : covered;
    await _writeMarker(_coveredKey, newCovered);
  }

  Future<void> _rebuild(CivilDateRange range) async {
    final history = await _resolution.read(range);

    await _db.transaction(() async {
      await (_db.delete(_db.occurrenceRollups)
            ..where((t) => t.spanEnd.isBiggerOrEqualValue(range.start.epochDay)))
          .go();

      for (final entry in history.byCommitment.entries) {
        for (final r in entry.value) {
          await _db.into(_db.occurrenceRollups).insertOnConflictUpdate(
                OccurrenceRollupsCompanion.insert(
                  commitmentId: entry.key,
                  scope: r.occurrence.scope,
                  spanStart: r.occurrence.span.start,
                  spanEnd: r.occurrence.span.end,
                  status: r.status,
                  completed: r.completed,
                  target: r.target,
                  credit: r.credit,
                ),
              );
        }
      }
    });
  }

  /// Aggregates rollups without touching raw events.
  ///
  /// This is the method the year screen calls, and the reason the table exists.
  Future<ConsistencySummary> summaryFor(
    CivilDateRange range, {
    String? commitmentId,
  }) async =>
      _summarise(await _rows(range, commitmentId));

  /// Consistency per bucket — months of a year, for instance.
  Future<Map<CivilDate, ConsistencySummary>> bucketed({
    required CivilDateRange range,
    required CivilDate Function(CivilDate) bucketOf,
    String? commitmentId,
  }) async {
    final rows = await _rows(range, commitmentId);
    final groups = <CivilDate, List<RollupRow>>{};
    for (final row in rows) {
      groups.putIfAbsent(bucketOf(row.spanEnd), () => []).add(row);
    }
    final keys = groups.keys.toList()..sort();
    return {for (final k in keys) k: _summarise(groups[k]!)};
  }

  Future<List<RollupRow>> _rows(CivilDateRange range, String? commitmentId) {
    final query = _db.select(_db.occurrenceRollups)
      ..where((t) => t.spanEnd.isBetweenValues(
            range.start.epochDay,
            range.end.epochDay,
          ));
    if (commitmentId != null) {
      query.where((t) => t.commitmentId.equals(commitmentId));
    }
    return query.get();
  }

  ConsistencySummary _summarise(List<RollupRow> rows) {
    var done = 0, partial = 0, missed = 0, skipped = 0, pending = 0;
    var credit = 0.0;
    for (final row in rows) {
      switch (row.status.name) {
        case 'done':
          done++;
        case 'partial':
          partial++;
        case 'missed':
          missed++;
        case 'skipped':
          skipped++;
        case 'pending':
          pending++;
      }
      credit += row.credit;
    }
    return ConsistencySummary(
      done: done,
      partial: partial,
      missed: missed,
      skipped: skipped,
      pending: pending,
      weightedCompletion: credit,
    );
  }

  Future<CivilDate?> _readMarker(String key) async {
    final row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    if (row == null) return null;
    return CivilDate.fromEpochDay(int.parse(row.value));
  }

  Future<void> _writeMarker(String key, CivilDate value) =>
      _db.into(_db.settings).insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: key,
              value: '${value.epochDay}',
            ),
          );

  Future<void> _clearMarker(String key) =>
      (_db.delete(_db.settings)..where((t) => t.key.equals(key))).go();
}
