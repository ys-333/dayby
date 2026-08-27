/// A calendar date with no time and no timezone — the unit scheduling is
/// expressed in. Deliberately not a [DateTime]: a `DateTime` carries a time and
/// a UTC/local flag, and mixing those into schedule arithmetic is how DST bugs
/// get in. Instants (event timestamps) stay `DateTime`; dates are [CivilDate].
///
/// Internal arithmetic goes through `DateTime.utc`, which has no DST, so day
/// and month math is exact and leap years come for free.
class CivilDate implements Comparable<CivilDate> {
  const CivilDate(this.year, this.month, this.day);

  factory CivilDate.fromEpochDay(int epochDay) {
    final dt = DateTime.utc(1970).add(Duration(days: epochDay));
    return CivilDate(dt.year, dt.month, dt.day);
  }

  /// Parses `yyyy-MM-dd`. Throws [FormatException] on anything else.
  factory CivilDate.parse(String iso) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
    if (m == null) throw FormatException('not a yyyy-MM-dd date', iso);
    return CivilDate(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  final int year;
  final int month;
  final int day;

  int get epochDay =>
      DateTime.utc(year, month, day).millisecondsSinceEpoch ~/ 86400000;

  /// 1 = Monday … 7 = Sunday, matching [DateTime.weekday].
  int get weekday => DateTime.utc(year, month, day).weekday;

  CivilDate plusDays(int n) => CivilDate.fromEpochDay(epochDay + n);

  CivilDate startOfWeek(int weekStartsOn) =>
      plusDays(-((weekday - weekStartsOn + 7) % 7));

  CivilDate get startOfMonth => CivilDate(year, month, 1);

  CivilDate get endOfMonth {
    // month + 1 normalises past December inside DateTime.utc.
    final dt = DateTime.utc(year, month + 1, 1)
        .subtract(const Duration(days: 1));
    return CivilDate(dt.year, dt.month, dt.day);
  }

  /// Inclusive day count from this date to [other].
  int daysUntil(CivilDate other) => other.epochDay - epochDay;

  String get iso =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  bool operator <(CivilDate o) => epochDay < o.epochDay;
  bool operator <=(CivilDate o) => epochDay <= o.epochDay;
  bool operator >(CivilDate o) => epochDay > o.epochDay;
  bool operator >=(CivilDate o) => epochDay >= o.epochDay;

  @override
  int compareTo(CivilDate o) => epochDay.compareTo(o.epochDay);

  @override
  bool operator ==(Object other) =>
      other is CivilDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => iso;
}

/// An inclusive range of dates. Used for schedule validity, pauses and periods.
class CivilDateRange {
  const CivilDateRange(this.start, this.end);

  final CivilDate start;
  final CivilDate end;

  bool contains(CivilDate d) => d >= start && d <= end;
  int get lengthInDays => start.daysUntil(end) + 1;

  Iterable<CivilDate> get dates =>
      Iterable.generate(lengthInDays, (i) => start.plusDays(i));

  @override
  bool operator ==(Object other) =>
      other is CivilDateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '${start.iso}..${end.iso}';
}
