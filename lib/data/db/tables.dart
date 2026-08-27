import 'package:drift/drift.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/time/accounting_calendar.dart';

import 'converters.dart';

/// Discriminator for the stored frequency union.
///
/// Stored as separate columns rather than serialised JSON: the fields are
/// queryable, migrations can alter them individually, and nothing has to parse
/// a blob to answer "which commitments are weekly".
enum StoredFrequencyType {
  daily,
  weekdays,
  everyNDays,
  timesPerWeek,
  timesPerMonth,
}

@DataClassName('CommitmentRow')
class Commitments extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get icon => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  IntColumn get startedOn => integer().map(const CivilDateConverter())();
  IntColumn get state => intEnum<CommitmentState>()();
  IntColumn get archivedOn =>
      integer().map(const CivilDateConverter()).nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer().map(const UtcInstantConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ScheduleRow')
class CommitmentSchedules extends Table {
  TextColumn get id => text()();
  TextColumn get commitmentId =>
      text().references(Commitments, #id, onDelete: KeyAction.cascade)();
  IntColumn get effectiveFrom => integer().map(const CivilDateConverter())();
  IntColumn get effectiveTo =>
      integer().map(const CivilDateConverter()).nullable()();
  IntColumn get frequencyType => intEnum<StoredFrequencyType>()();
  IntColumn get target => integer().withDefault(const Constant(1))();

  /// Bitmask of weekdays, bit 0 = Monday. Only meaningful for `weekdays`.
  IntColumn get daysOfWeekMask => integer().withDefault(const Constant(0))();

  /// Interval, only meaningful for `everyNDays`.
  IntColumn get everyNDays => integer().nullable()();
  IntColumn get targetMinutes => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TrackingEventRow')
class TrackingEvents extends Table {
  TextColumn get id => text()();
  TextColumn get commitmentId =>
      text().references(Commitments, #id, onDelete: KeyAction.cascade)();

  /// The accounting day this counts toward — not the day it was entered.
  IntColumn get accountingDate => integer().map(const CivilDateConverter())();
  IntColumn get recordedAtUtc => integer().map(const UtcInstantConverter())();
  IntColumn get kind => intEnum<TrackingKind>()();
  IntColumn get count => integer().withDefault(const Constant(1))();
  IntColumn get minutes => integer().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PausePeriodRow')
class PausePeriods extends Table {
  TextColumn get id => text()();
  TextColumn get commitmentId =>
      text().references(Commitments, #id, onDelete: KeyAction.cascade)();
  IntColumn get fromDay => integer().map(const CivilDateConverter())();
  IntColumn get toDay => integer().map(const CivilDateConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

/// Key-value settings. A table rather than shared preferences so a backup of
/// the database is a complete backup — the day boundary and timezone are
/// required to interpret every stored date.
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Materialised resolved occurrences — derived data, never a source of truth.
///
/// The year screen aggregates a few hundred of these instead of re-resolving a
/// year of raw events on every render. Everything here can be thrown away and
/// rebuilt from commitments, schedules, events and pauses; if it ever disagrees
/// with those, the rollup is wrong by definition.
@DataClassName('RollupRow')
class OccurrenceRollups extends Table {
  TextColumn get commitmentId =>
      text().references(Commitments, #id, onDelete: KeyAction.cascade)();
  IntColumn get scope => intEnum<PeriodScope>()();
  IntColumn get spanStart => integer().map(const CivilDateConverter())();
  IntColumn get spanEnd => integer().map(const CivilDateConverter())();
  IntColumn get status => intEnum<OccurrenceStatus>()();
  IntColumn get completed => integer()();
  IntColumn get target => integer()();
  RealColumn get credit => real()();

  @override
  Set<Column> get primaryKey => {commitmentId, scope, spanStart};
}
