import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/pause_period.dart';
import 'package:riyaz/domain/model/schedule.dart';
import 'package:riyaz/domain/model/tracking_event.dart';

import 'app_database.dart';
import 'converters.dart';
import 'tables.dart';

/// Translation between storage rows and domain models.
///
/// The domain never sees a row and the database never sees a sealed union;
/// keeping the mapping in one file means a schema change has exactly one place
/// to break, loudly.
extension CommitmentMapper on CommitmentRow {
  Commitment toDomain() => Commitment(
        id: id,
        name: name,
        startedOn: startedOn,
        description: description,
        icon: icon,
        categoryId: categoryId,
        state: state,
        archivedOn: archivedOn,
      );
}

extension ScheduleMapper on ScheduleRow {
  Frequency toFrequency() => switch (frequencyType) {
        StoredFrequencyType.daily => Frequency.daily(target: target),
        StoredFrequencyType.weekdays => Frequency.weekdays(
            days: maskToWeekdays(daysOfWeekMask),
            target: target,
          ),
        StoredFrequencyType.everyNDays => Frequency.everyNDays(
            n: everyNDays ?? 1,
            target: target,
          ),
        StoredFrequencyType.timesPerWeek =>
          Frequency.timesPerWeek(target: target),
        StoredFrequencyType.timesPerMonth =>
          Frequency.timesPerMonth(target: target),
      };

  CommitmentSchedule toDomain() => CommitmentSchedule(
        id: id,
        commitmentId: commitmentId,
        effectiveFrom: effectiveFrom,
        effectiveTo: effectiveTo,
        frequency: toFrequency(),
        targetMinutes: targetMinutes,
      );
}

extension TrackingEventMapper on TrackingEventRow {
  TrackingEvent toDomain() => TrackingEvent(
        id: id,
        commitmentId: commitmentId,
        accountingDate: accountingDate,
        recordedAtUtc: recordedAtUtc,
        kind: kind,
        count: count,
        minutes: minutes,
        note: note,
      );
}

extension PauseMapper on PausePeriodRow {
  PausePeriod toDomain() => PausePeriod(
        id: id,
        commitmentId: commitmentId,
        from: fromDay,
        to: toDay,
      );
}

/// Decomposes a frequency union into its stored columns.
({
  StoredFrequencyType type,
  int target,
  int daysMask,
  int? everyN,
}) frequencyToColumns(Frequency frequency) => switch (frequency) {
      DailyFrequency(:final target) => (
          type: StoredFrequencyType.daily,
          target: target,
          daysMask: 0,
          everyN: null,
        ),
      WeekdaysFrequency(:final days, :final target) => (
          type: StoredFrequencyType.weekdays,
          target: target,
          daysMask: weekdaysToMask(days),
          everyN: null,
        ),
      EveryNDaysFrequency(:final n, :final target) => (
          type: StoredFrequencyType.everyNDays,
          target: target,
          daysMask: 0,
          everyN: n,
        ),
      TimesPerWeekFrequency(:final target) => (
          type: StoredFrequencyType.timesPerWeek,
          target: target,
          daysMask: 0,
          everyN: null,
        ),
      TimesPerMonthFrequency(:final target) => (
          type: StoredFrequencyType.timesPerMonth,
          target: target,
          daysMask: 0,
          everyN: null,
        ),
    };
