/// When the user wants to be reminded, and about what.
///
/// Pure data. The persisted form lives in `lib/data/`; this is what the
/// scheduling rules reason about.
///
/// Both reminders default **off**. A tracker that notifies before being asked
/// to is a tracker that gets its notifications switched off at the OS level,
/// and that setting is far harder to win back than an in-app toggle.
class ReminderSettings {
  const ReminderSettings({
    this.dailyEnabled = false,
    this.hour = 8,
    this.minute = 0,
    this.weeklyReviewEnabled = false,
  });

  final bool dailyEnabled;

  /// Local wall-clock time, 0–23. Not an offset from the day boundary: the user
  /// picks "08:00" on a clock, and that has to survive DST unchanged.
  final int hour;
  final int minute;

  final bool weeklyReviewEnabled;

  /// True when nothing needs scheduling at all.
  bool get isSilent => !dailyEnabled && !weeklyReviewEnabled;

  ReminderSettings copyWith({
    bool? dailyEnabled,
    int? hour,
    int? minute,
    bool? weeklyReviewEnabled,
  }) =>
      ReminderSettings(
        dailyEnabled: dailyEnabled ?? this.dailyEnabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        weeklyReviewEnabled: weeklyReviewEnabled ?? this.weeklyReviewEnabled,
      );

  @override
  bool operator ==(Object other) =>
      other is ReminderSettings &&
      other.dailyEnabled == dailyEnabled &&
      other.hour == hour &&
      other.minute == minute &&
      other.weeklyReviewEnabled == weeklyReviewEnabled;

  @override
  int get hashCode => Object.hash(dailyEnabled, hour, minute, weeklyReviewEnabled);

  @override
  String toString() => 'ReminderSettings(daily: $dailyEnabled at '
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}, '
      'weekly: $weeklyReviewEnabled)';
}
