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

  /// Suspends a commitment from [from], until [to] or until it is resumed.
  ///
  /// A pause is the *only* correct way to stop expecting something for a
  /// while. `CommitmentState.paused` exists on the model and has never had a
  /// single reader: `lib/domain/` consults `PausePeriods` and nothing else
  /// (`recurrence_engine.dart:34`, `accounting_engine.dart:162`). Setting the
  /// flag instead would look right on screen, change nothing the engine sees,
  /// and quietly bank a miss a day for the whole "pause" — the same failure
  /// archiving shipped with.
  ///
  /// **At most one open pause per commitment.** Two overlapping open pauses
  /// would both cover every future day, so resuming would close one and leave
  /// the other still suspending everything — a state the user cannot see and
  /// cannot get out of. Starting a new pause therefore closes any open one the
  /// day before the new one begins, and drops it entirely if that leaves it
  /// covering nothing.
  Future<void> pauseCommitment({
    required String commitmentId,
    required CivilDate from,
    CivilDate? to,
  }) async {
    await _db.transaction(() async {
      await _closeOpenPauses(commitmentId, at: from.plusDays(-1));
      await _db.into(_db.pausePeriods).insert(PausePeriodsCompanion.insert(
            id: _ids.next('p'),
            commitmentId: commitmentId,
            fromDay: from,
            toDay: Value(to),
          ));
    });
    await onWrite?.call(from);
  }

  /// Ends the open pause, making [on] the first day expected again.
  ///
  /// The pause's last covered day is `on - 1`: resuming *on* a day means that
  /// day is lived normally. Pausing and resuming the same day leaves a pause
  /// covering nothing, and that row is deleted rather than stored — an end
  /// before its own start is a row every future reader would have to know to
  /// skip.
  ///
  /// Returns the date rollups were invalidated from, or null when there was no
  /// open pause to end.
  ///
  /// Invalidation runs from the pause's **start**, not from [on]. Only days
  /// after `on` change status, so the narrower range would be enough — but a
  /// rollup is a cache and the cost of rebuilding a few extra days is a
  /// rounding error against the cost of one stale row that nothing ever
  /// corrects. `pauseCommitment` already takes the same wide view.
  Future<CivilDate?> resumeCommitment({
    required String commitmentId,
    required CivilDate on,
  }) async {
    final open = await _openPause(commitmentId);
    if (open == null) return null;

    await _db.transaction(
      () => _closeOpenPauses(commitmentId, at: on.plusDays(-1)),
    );
    await onWrite?.call(open.fromDay);
    return open.fromDay;
  }

  /// The commitment's open-ended pause, if it has one.
  Future<PausePeriodRow?> _openPause(String commitmentId) =>
      (_db.select(_db.pausePeriods)
            ..where((t) => t.commitmentId.equals(commitmentId) &
                t.toDay.isNull()))
          .getSingleOrNull();

  /// Closes every open pause at [at], deleting any left covering no day.
  ///
  /// Plural and unconditional despite the one-open-pause invariant: this is
  /// what *enforces* it, and a database restored from a hand-edited backup can
  /// arrive holding two. Repairing that silently is better than honouring it.
  Future<void> _closeOpenPauses(
    String commitmentId, {
    required CivilDate at,
  }) async {
    await (_db.delete(_db.pausePeriods)
          ..where((t) => t.commitmentId.equals(commitmentId) &
              t.toDay.isNull() &
              t.fromDay.isBiggerThanValue(at.epochDay)))
        .go();
    await (_db.update(_db.pausePeriods)
          ..where((t) => t.commitmentId.equals(commitmentId) &
              t.toDay.isNull()))
        .write(PausePeriodsCompanion(toDay: Value(at)));
  }

  /// Edits a commitment. Fields left null are untouched.
  ///
  /// Name, icon and description are plain writes — they describe the
  /// commitment, not what it expected of you, so changing them cannot alter a
  /// single historical number.
  ///
  /// [frequency] is different, and is the reason this method is careful.
  /// The **schedule is the source of truth for what was expected**, so
  /// rewriting the current schedule row in place would retroactively change
  /// what every past day was measured against: switch a year-old daily habit
  /// to 3×/week and every one of those days would silently re-resolve against
  /// a target it was never held to. Consistency for last March would move.
  ///
  /// So a frequency change is **effective-dated**: the version in force is
  /// closed the day before [on], and a new one opens on [on]. The past keeps
  /// the rules it was actually lived under.
  ///
  /// The one case that amends in place rather than versioning is a schedule
  /// that already begins on or after [on] — editing twice in a day, or editing
  /// a commitment created today. Closing that one at `on - 1` would leave a
  /// version whose end precedes its start: an empty, meaningless row that
  /// every reader would then have to know to skip. Amending is not the tidier
  /// choice there, it is the only correct one.
  Future<void> updateCommitment({
    required String commitmentId,
    required CivilDate on,
    String? name,
    String? icon,
    /// Removes the icon rather than leaving it. A null [icon] means "not
    /// changing this", which is the right default for a partial edit but
    /// leaves no way to say "no mark at all" — so clearing gets its own flag
    /// instead of overloading null with two meanings.
    bool clearIcon = false,
    String? description,
    Frequency? frequency,
    int? targetMinutes,
  }) async {
    CivilDate? changedFrom;

    await _db.transaction(() async {
      if (name != null || icon != null || clearIcon || description != null) {
        await (_db.update(_db.commitments)
              ..where((t) => t.id.equals(commitmentId)))
            .write(CommitmentsCompanion(
          name: name == null ? const Value.absent() : Value(name),
          icon: clearIcon
              ? const Value(null)
              : icon == null
                  ? const Value.absent()
                  : Value(icon),
          description: description == null
              ? const Value.absent()
              : Value(description),
        ));
      }
      if (frequency == null) return;

      final open = await (_db.select(_db.commitmentSchedules)
            ..where((t) =>
                t.commitmentId.equals(commitmentId) & t.effectiveTo.isNull()))
          .getSingleOrNull();
      if (open == null) return; // archived: its schedule is closed on purpose.

      final columns = frequencyToColumns(frequency);

      if (open.effectiveFrom >= on) {
        await (_db.update(_db.commitmentSchedules)
              ..where((t) => t.id.equals(open.id)))
            .write(CommitmentSchedulesCompanion(
          frequencyType: Value(columns.type),
          target: Value(columns.target),
          daysOfWeekMask: Value(columns.daysMask),
          everyNDays: Value(columns.everyN),
          targetMinutes: Value(targetMinutes),
        ));
        changedFrom = open.effectiveFrom;
        return;
      }

      await (_db.update(_db.commitmentSchedules)
            ..where((t) => t.id.equals(open.id)))
          .write(CommitmentSchedulesCompanion(
        effectiveTo: Value(on.plusDays(-1)),
      ));
      await _db
          .into(_db.commitmentSchedules)
          .insert(CommitmentSchedulesCompanion.insert(
            id: _ids.next('s'),
            commitmentId: commitmentId,
            effectiveFrom: on,
            frequencyType: columns.type,
            target: Value(columns.target),
            daysOfWeekMask: Value(columns.daysMask),
            everyNDays: Value(columns.everyN),
            targetMinutes: Value(targetMinutes),
          ));
      changedFrom = on;
    });

    // Only a schedule change moves any number, and only from its effective
    // date forward. A rename invalidates nothing.
    if (changedFrom != null) await onWrite?.call(changedFrom!);
  }

  /// Archives on [on], and closes the schedule on the same day.
  ///
  /// Closing the schedule is the part that matters. `lib/domain/` reads
  /// neither `state` nor `archivedOn` — by design, since the **schedule** is
  /// the source of truth for what was expected. Flipping the flag alone
  /// therefore changes nothing the engine can see: the commitment keeps
  /// generating expected occurrences forever, and every one of them turns
  /// MISSED as its day closes. Archive a daily commitment and your consistency
  /// bleeds a miss a day, indefinitely, with nothing anywhere throwing.
  ///
  /// So archiving ends the schedule rather than marking the commitment. Both
  /// writes are one transaction: a commitment archived with its schedule still
  /// open is precisely the corrupt state this exists to prevent.
  Future<void> archiveCommitment(String commitmentId, CivilDate on) async {
    await _db.transaction(() async {
      await (_db.update(_db.commitments)
            ..where((t) => t.id.equals(commitmentId)))
          .write(CommitmentsCompanion(
        state: const Value(CommitmentState.archived),
        archivedOn: Value(on),
      ));
      await (_db.update(_db.commitmentSchedules)
            ..where((t) =>
                t.commitmentId.equals(commitmentId) & t.effectiveTo.isNull()))
          .write(CommitmentSchedulesCompanion(effectiveTo: Value(on)));
    });
    // Days from the archive onward now resolve differently, so any rollup
    // covering them is stale. The earlier claim that archiving needed no
    // invalidation was true only for dates at or before the archive date.
    await onWrite?.call(on);
  }

  /// Puts it back, reopening the schedule that archiving closed.
  ///
  /// Only the version closed on the stored archive date is reopened, so a
  /// schedule that genuinely ended on some other day is left alone.
  Future<void> unarchiveCommitment(String commitmentId) async {
    final row = await (_db.select(_db.commitments)
          ..where((t) => t.id.equals(commitmentId)))
        .getSingleOrNull();
    final archivedOn = row?.archivedOn;

    await _db.transaction(() async {
      await (_db.update(_db.commitments)
            ..where((t) => t.id.equals(commitmentId)))
          .write(const CommitmentsCompanion(
        state: Value(CommitmentState.active),
        archivedOn: Value(null),
      ));
      if (archivedOn != null) {
        await (_db.update(_db.commitmentSchedules)
              ..where((t) =>
                  t.commitmentId.equals(commitmentId) &
                  t.effectiveTo.equalsValue(archivedOn)))
            .write(const CommitmentSchedulesCompanion(
          effectiveTo: Value(null),
        ));
      }
    });
    if (archivedOn != null) await onWrite?.call(archivedOn);
  }

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
