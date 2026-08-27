/// Settings that change how stored data is interpreted.
///
/// These live with the data, not in shared preferences: the day boundary and
/// timezone are required to read every stored date correctly, so a backup
/// without them would be ambiguous.
class AppSettings {
  const AppSettings({
    this.timezoneName = defaultTimezone,
    this.dayBoundaryHour = 4,
    this.weekStartsOn = DateTime.monday,
  });

  /// Until the timezone is user-selectable, this is the assumed zone.
  ///
  /// Detecting the device's IANA zone needs a plugin (`flutter_timezone`);
  /// `DateTime.now().timeZoneName` only yields an abbreviation, which is
  /// ambiguous and useless for DST arithmetic. Rather than add a dependency
  /// unasked, the zone is a stored setting with this default.
  static const String defaultTimezone = 'Asia/Kolkata';

  final String timezoneName;
  final int dayBoundaryHour;
  final int weekStartsOn;

  AppSettings copyWith({
    String? timezoneName,
    int? dayBoundaryHour,
    int? weekStartsOn,
  }) =>
      AppSettings(
        timezoneName: timezoneName ?? this.timezoneName,
        dayBoundaryHour: dayBoundaryHour ?? this.dayBoundaryHour,
        weekStartsOn: weekStartsOn ?? this.weekStartsOn,
      );
}
