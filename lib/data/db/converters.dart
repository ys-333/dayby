import 'package:drift/drift.dart';
import 'package:riyaz/domain/time/civil_date.dart';

/// Stores a [CivilDate] as an epoch day.
///
/// An integer, not a string: dates are compared and ranged constantly, and
/// integer comparison in SQL is both correct and indexable. The civil date
/// carries no timezone, so this is a lossless, stable encoding.
class CivilDateConverter extends TypeConverter<CivilDate, int> {
  const CivilDateConverter();

  @override
  CivilDate fromSql(int fromDb) => CivilDate.fromEpochDay(fromDb);

  @override
  int toSql(CivilDate value) => value.epochDay;
}

/// Stores an instant as UTC milliseconds. Event timestamps are instants and
/// stay instants — never mixed with the civil dates above.
class UtcInstantConverter extends TypeConverter<DateTime, int> {
  const UtcInstantConverter();

  @override
  DateTime fromSql(int fromDb) =>
      DateTime.fromMillisecondsSinceEpoch(fromDb, isUtc: true);

  @override
  int toSql(DateTime value) => value.toUtc().millisecondsSinceEpoch;
}

/// Packs weekdays into a bitmask, bit 0 = Monday.
int weekdaysToMask(Set<int> days) =>
    days.fold(0, (mask, day) => mask | (1 << (day - 1)));

Set<int> maskToWeekdays(int mask) =>
    {for (var day = 1; day <= 7; day++) if (mask & (1 << (day - 1)) != 0) day};
