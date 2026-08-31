import 'package:flutter/material.dart';

/// How the app chooses between its light and dark themes.
///
/// **Deliberately not part of [AppSettings].** That class holds settings which
/// change how stored data is *interpreted* — the timezone and day boundary
/// travel inside every backup because a stored civil date is ambiguous without
/// them. A theme choice interprets nothing. Restoring a backup onto a new phone
/// and finding the theme at its default is correct behaviour rather than data
/// loss, and carrying it in the document would force `currentVersion` to 3 and
/// make every older build refuse the file over a cosmetic preference.
///
/// Three states, not a two-way switch: dropping "system" would be a downgrade
/// for anyone whose phone already changes theme on a schedule.
abstract final class ThemePreference {
  static const String key = 'settings.themeMode';

  /// What an unset — or unreadable — preference means.
  static const ThemeMode fallback = ThemeMode.system;

  static const List<ThemeMode> choices = [
    ThemeMode.system,
    ThemeMode.light,
    ThemeMode.dark,
  ];

  static String encode(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'system',
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
      };

  /// Stored values are strings and a hand-repaired backup can hold anything, so
  /// an unrecognised value means "follow the system" rather than a crash before
  /// the first frame — this is read on the startup path.
  static ThemeMode decode(String? raw) => switch (raw) {
        'system' => ThemeMode.system,
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => fallback,
      };

  static String label(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };
}
