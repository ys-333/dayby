import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/data/repository/settings_repository.dart';
import 'package:riyaz/domain/notifications/reminder_settings.dart';
import 'package:riyaz/features/notifications/notification_gateway.dart';
import 'package:riyaz/features/notifications/reminder_scheduler.dart';

part 'reminder_settings_controller.g.dart';

/// How [ReminderSettings] is stored, and how it survives a hand-edited row.
///
/// Kept out of `AppSettings` for the same reason the theme is: that class holds
/// settings which change how stored data is *interpreted*, and its three fields
/// travel inside every backup because a stored civil date is ambiguous without
/// them. A reminder time interprets nothing. Restoring a backup onto a new phone
/// and finding reminders at their defaults is correct behaviour rather than data
/// loss, and carrying them in the document would force
/// `BackupDocument.currentVersion` up over a preference.
abstract final class ReminderPreference {
  static const String dailyEnabledKey = 'reminder.daily.enabled';
  static const String timeKey = 'reminder.daily.time';
  static const String weeklyEnabledKey = 'reminder.weekly.enabled';

  static String encodeTime(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// Parses `HH:mm`, rejecting anything out of range.
  ///
  /// Returns null rather than a partial result, so the caller falls back to the
  /// default as a whole. An hour of 25 would not throw — it would schedule a
  /// reminder at a time that does not exist, which fails silently and is far
  /// harder to notice than a value that simply reverts.
  static (int, int)? decodeTime(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }

  static bool decodeFlag(String? raw) => raw == 'true';

  static String encodeFlag(bool value) => value ? 'true' : 'false';

  static Future<ReminderSettings> load(SettingsRepository repository) async {
    const defaults = ReminderSettings();
    final time = decodeTime(await repository.readRaw(timeKey));
    return ReminderSettings(
      dailyEnabled: decodeFlag(await repository.readRaw(dailyEnabledKey)),
      hour: time?.$1 ?? defaults.hour,
      minute: time?.$2 ?? defaults.minute,
      weeklyReviewEnabled:
          decodeFlag(await repository.readRaw(weeklyEnabledKey)),
    );
  }

  static Future<void> save(
    SettingsRepository repository,
    ReminderSettings settings,
  ) async {
    await repository.writeRaw(
        dailyEnabledKey, encodeFlag(settings.dailyEnabled));
    await repository.writeRaw(
        weeklyEnabledKey, encodeFlag(settings.weeklyReviewEnabled));
    await repository.writeRaw(
        timeKey, encodeTime(settings.hour, settings.minute));
  }
}

/// The reminder settings the app started with. Overridden in `main()`.
@Riverpod(keepAlive: true)
ReminderSettings initialReminderSettings(Ref ref) => const ReminderSettings();

/// The live reminder settings, and the only way to change them.
///
/// Every change persists and then reschedules, in that order. Rescheduling
/// against a value that failed to save would leave the platform holding
/// notifications the app no longer believes in.
@Riverpod(keepAlive: true)
class ReminderSettingsController extends _$ReminderSettingsController {
  @override
  ReminderSettings build() => ref.watch(initialReminderSettingsProvider);

  Future<void> update(ReminderSettings next) async {
    await ReminderPreference.save(ref.read(settingsRepositoryProvider), next);
    state = next;
    await ref.read(reminderSchedulerProvider).reschedule();
  }

  /// Turns the daily reminder on or off.
  ///
  /// Returns **false when the OS refused permission**, in which case nothing
  /// was changed and nothing was stored. A toggle left reading "on" while
  /// Android silently blocks delivery is a lie the user cannot debug — they
  /// would conclude the feature is broken, which it would be, invisibly.
  ///
  /// Permission is requested here, on first enable, rather than at startup. A
  /// prompt before the user has shown any interest is how an app gets
  /// permanently denied, and the OS-level block is far harder to win back than
  /// an in-app switch.
  Future<bool> setDailyEnabled(bool enabled) async {
    if (enabled && !await _permitted()) return false;
    await update(state.copyWith(dailyEnabled: enabled));
    return true;
  }

  Future<bool> setWeeklyReviewEnabled(bool enabled) async {
    if (enabled && !await _permitted()) return false;
    await update(state.copyWith(weeklyReviewEnabled: enabled));
    return true;
  }

  Future<void> setTime(int hour, int minute) =>
      update(state.copyWith(hour: hour, minute: minute));

  Future<bool> _permitted() =>
      ref.read(notificationGatewayProvider).ensurePermission();
}
