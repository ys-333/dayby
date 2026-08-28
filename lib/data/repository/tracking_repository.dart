import 'package:drift/drift.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/pause_period.dart';
import 'package:riyaz/domain/model/schedule.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/time/civil_date.dart';

import '../db/app_database.dart';
import '../db/mappers.dart';
import '../ids.dart';

/// Everything the engines need to resolve a date range, in one value.
class TrackingSnapshot {
  const TrackingSnapshot({
    required this.commitments,
    required this.schedules,
    required this.pauses,
    required this.events,
  });

  static const TrackingSnapshot empty = TrackingSnapshot(
    commitments: [],
    schedules: {},
    pauses: {},
    events: [],
  );

  final List<Commitment> commitments;
  final Map<String, List<CommitmentSchedule>> schedules;
  final Map<String, List<PausePeriod>> pauses;
  final List<TrackingEvent> events;

  List<CommitmentSchedule> schedulesFor(String id) => schedules[id] ?? const [];
  List<PausePeriod> pausesFor(String id) => pauses[id] ?? const [];
}

/// Captures the state a write replaced, so it can be put back exactly.
///
/// Undo restores the full set of events for one commitment-day rather than
/// reversing a specific operation. That is uniform across mark-done,
/// increment, partial, skip, note and edit — one mechanism instead of an
/// inverse per action, and no operation can be forgotten. One-tap tracking
/// guarantees accidental taps, so undo has to be total.
class UndoToken {
  const UndoToken({
    required this.commitmentId,
    required this.date,
    required this.previous,
    required this.label,
  });

  final String commitmentId;
  final CivilDate date;
  final List<TrackingEvent> previous;

  /// Shown in the snackbar: "Running marked done".
  final String label;
}

class TrackingRepository {
  TrackingRepository(this._db, {IdGenerator? ids})
      : _ids = ids ?? IdGenerator();

  final AppDatabase _db;
  final IdGenerator _ids;

  /// Notified with the earliest date a write could have affected, so derived
  /// data knows what to recompute. Set by the composition root; null in tests
  /// that exercise storage alone.
  ///
  /// Returns a future and every caller awaits it. Fire-and-forget would race:
  /// a read issued straight after a write could observe the invalidation marker
  /// before it had been written, and silently serve stale rollups.
  Future<void> Function(CivilDate from)? onWrite;

  // ---------------------------------------------------------------- reading

  /// Live snapshot covering [range]. Emits once immediately, then on every
  /// write to any table it depends on.
  ///
  /// Re-reads the whole range rather than diffing. At one person's scale that
  /// is a few hundred rows and the simplicity is worth far more than the saved
  /// microseconds — and it avoids a stream-combination dependency for a join
  /// the database can already express.
  Stream<TrackingSnapshot> watch(CivilDateRange range) async* {
    yield await read(range);
    final updates = _db.tableUpdates(TableUpdateQuery.onAllTables([
      _db.commitments,
      _db.commitmentSchedules,
      _db.pausePeriods,
      _db.trackingEvents,
    ]));
    // yield* rather than `await for`: it delegates cancellation to the inner
    // subscription, so closing the screen actually tears the watch down.
    yield* updates.asyncMap((_) => read(range));
  }

  Future<TrackingSnapshot> read(CivilDateRange range) async {
    final commitments = await _db.select(_db.commitments).get();
    final schedules = await _db.select(_db.commitmentSchedules).get();
    final pauses = await _db.select(_db.pausePeriods).get();
    final events = await (_db.select(_db.trackingEvents)
          ..where((t) => t.accountingDate.isBetweenValues(
                range.start.epochDay,
                range.end.epochDay,
              )))
        .get();
    return _assemble(commitments, schedules, pauses, events);
  }

  /// Everything, unfiltered by date. For export only — screens must use a
  /// bounded range so a year of history never lands in a widget build.
  Future<TrackingSnapshot> readAll() async => _assemble(
        await _db.select(_db.commitments).get(),
        await _db.select(_db.commitmentSchedules).get(),
        await _db.select(_db.pausePeriods).get(),
        await _db.select(_db.trackingEvents).get(),
      );

  TrackingSnapshot _assemble(
    List<CommitmentRow> commitments,
    List<ScheduleRow> schedules,
    List<PausePeriodRow> pauses,
    List<TrackingEventRow> events,
  ) {
    final schedulesById = <String, List<CommitmentSchedule>>{};
    for (final s in schedules) {
      schedulesById.putIfAbsent(s.commitmentId, () => []).add(s.toDomain());
    }
    final pausesById = <String, List<PausePeriod>>{};
    for (final p in pauses) {
      pausesById.putIfAbsent(p.commitmentId, () => []).add(p.toDomain());
    }
    final ordered = [...commitments]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return TrackingSnapshot(
      commitments: [for (final c in ordered) c.toDomain()],
      schedules: schedulesById,
      pauses: pausesById,
      events: [for (final e in events) e.toDomain()],
    );
  }

  // ---------------------------------------------------------------- writing

  /// Creates a commitment with its first schedule version.
  Future<String> createCommitment({
    required String name,
    required Frequency frequency,
    required CivilDate startedOn,
    required DateTime nowUtc,
    String? icon,
    String? description,
    int? targetMinutes,
  }) async {
    final id = _ids.next('c');
    final columns = frequencyToColumns(frequency);

    await _db.transaction(() async {
      final count = await _db.select(_db.commitments).get();
      await _db.into(_db.commitments).insert(CommitmentsCompanion.insert(
            id: id,
            name: name,
            startedOn: startedOn,
            state: CommitmentState.active,
            createdAt: nowUtc,
            icon: Value(icon),
            description: Value(description),
            sortOrder: Value(count.length),
          ));
      await _db
          .into(_db.commitmentSchedules)
          .insert(CommitmentSchedulesCompanion.insert(
            id: _ids.next('s'),
            commitmentId: id,
            effectiveFrom: startedOn,
            frequencyType: columns.type,
            target: Value(columns.target),
            daysOfWeekMask: Value(columns.daysMask),
            everyNDays: Value(columns.everyN),
            targetMinutes: Value(targetMinutes),
          ));
    });

    await onWrite?.call(startedOn);
    return id;
  }

  /// Records an event on [date], returning the token that reverses it.
  Future<UndoToken> record({
    required String commitmentId,
    required CivilDate date,
    required TrackingKind kind,
    required DateTime nowUtc,
    required String label,
    int count = 1,
    int? minutes,
    String? note,
  }) async {
    final previous = await _eventsOn(commitmentId, date);

    await _db.transaction(() async {
      // A skip is a statement about the whole day, so it replaces whatever was
      // there rather than coexisting with completions.
      if (kind == TrackingKind.skipped) {
        await _clearDay(commitmentId, date);
      }
      await _db.into(_db.trackingEvents).insert(
            TrackingEventsCompanion.insert(
              id: _ids.next('e'),
              commitmentId: commitmentId,
              accountingDate: date,
              recordedAtUtc: nowUtc,
              kind: kind,
              count: Value(count),
              minutes: Value(minutes),
              note: Value(note),
            ),
          );
    });

    await onWrite?.call(date);
    return UndoToken(
      commitmentId: commitmentId,
      date: date,
      previous: previous,
      label: label,
    );
  }

  /// Replaces everything recorded for one commitment-day.
  Future<UndoToken> replaceDay({
    required String commitmentId,
    required CivilDate date,
    required List<TrackingEvent> replacement,
    required String label,
  }) async {
    final previous = await _eventsOn(commitmentId, date);
    await _db.transaction(() async {
      await _clearDay(commitmentId, date);
      for (final e in replacement) {
        await _db.into(_db.trackingEvents).insert(_companionFor(e));
      }
    });
    await onWrite?.call(date);
    return UndoToken(
      commitmentId: commitmentId,
      date: date,
      previous: previous,
      label: label,
    );
  }

  /// Clears a commitment-day, e.g. un-ticking something ticked by mistake.
  Future<UndoToken> clear({
    required String commitmentId,
    required CivilDate date,
    required String label,
  }) =>
      replaceDay(
        commitmentId: commitmentId,
        date: date,
        replacement: const [],
        label: label,
      );

  /// Puts back exactly what was there before the write [token] describes.
  Future<void> undo(UndoToken token) async {
    await _db.transaction(() async {
      await _clearDay(token.commitmentId, token.date);
      for (final e in token.previous) {
        await _db.into(_db.trackingEvents).insert(_companionFor(e));
      }
    });
    await onWrite?.call(token.date);
  }

  Future<void> setNote({
    required String commitmentId,
    required CivilDate date,
    required String? note,
  }) async {
    final existing = await _eventsOn(commitmentId, date);
    if (existing.isEmpty) return;
    await (_db.update(_db.trackingEvents)
          ..where((t) => t.id.equals(existing.last.id)))
        .write(TrackingEventsCompanion(note: Value(note)));
    await onWrite?.call(date);
  }

  Future<void> pauseCommitment({
    required String commitmentId,
    required CivilDate from,
    required CivilDate to,
  }) async {
    await _db.into(_db.pausePeriods).insert(PausePeriodsCompanion.insert(
          id: _ids.next('p'),
          commitmentId: commitmentId,
          fromDay: from,
          toDay: to,
        ));
    await onWrite?.call(from);
  }

  Future<void> setState(String commitmentId, CommitmentState state,
      {CivilDate? archivedOn}) =>
      (_db.update(_db.commitments)..where((t) => t.id.equals(commitmentId)))
          .write(CommitmentsCompanion(
        state: Value(state),
        archivedOn: Value(archivedOn),
      ));

  // --------------------------------------------------------------- internals

  Future<List<TrackingEvent>> _eventsOn(String commitmentId, CivilDate date) =>
      (_db.select(_db.trackingEvents)
            ..where((t) =>
                t.commitmentId.equals(commitmentId) &
                t.accountingDate.equals(date.epochDay)))
          .get()
          .then((rows) => [for (final r in rows) r.toDomain()]);

  Future<void> _clearDay(String commitmentId, CivilDate date) =>
      (_db.delete(_db.trackingEvents)
            ..where((t) =>
                t.commitmentId.equals(commitmentId) &
                t.accountingDate.equals(date.epochDay)))
          .go();

  TrackingEventsCompanion _companionFor(TrackingEvent e) =>
      TrackingEventsCompanion.insert(
        id: e.id,
        commitmentId: e.commitmentId,
        accountingDate: e.accountingDate,
        recordedAtUtc: e.recordedAtUtc,
        kind: e.kind,
        count: Value(e.count),
        minutes: Value(e.minutes),
        note: Value(e.note),
      );
}
