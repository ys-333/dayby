import '../model/frequency.dart';
import '../model/pause_period.dart';
import '../model/schedule.dart';
import '../time/accounting_calendar.dart';
import '../time/civil_date.dart';
import 'expected_occurrence.dart';

/// Turns schedules into the occurrences they expected.
///
/// The schedule is the source of truth for what was expected — never the events
/// that happen to exist in storage. This engine therefore reads only schedules
/// and pauses, and knows nothing about what the user did.
class RecurrenceEngine {
  const RecurrenceEngine(this.calendar);

  final AccountingCalendar calendar;

  /// The schedule version in force on [date], or null if none was.
  ///
  /// Versions should not overlap; if they do, the latest `effectiveFrom` wins so
  /// the newer intent applies going forward without disturbing older dates.
  CommitmentSchedule? scheduleOn(
    List<CommitmentSchedule> schedules,
    CivilDate date,
  ) {
    CommitmentSchedule? best;
    for (final s in schedules) {
      if (!s.coversDate(date)) continue;
      if (best == null || s.effectiveFrom > best.effectiveFrom) best = s;
    }
    return best;
  }

  bool _isPaused(List<PausePeriod> pauses, CivilDate date) =>
      pauses.any((p) => p.covers(date));

  /// Whether a daily-shaped schedule expects something on [date].
  bool _dailyShapeMatches(CommitmentSchedule schedule, CivilDate date) {
    final f = schedule.frequency;
    return switch (f) {
      DailyFrequency() => true,
      WeekdaysFrequency(:final days) => days.contains(date.weekday),
      EveryNDaysFrequency(:final n) =>
        n > 0 && schedule.effectiveFrom.daysUntil(date) % n == 0,
      _ => false,
    };
  }

  /// Every occurrence expected in [range].
  ///
  /// Period occurrences are emitted once per (schedule version x period). A
  /// version that starts or ends mid-period yields a period **clipped** to the
  /// days it governs, with its target prorated to match.
  ///
  /// That rule is not free-floating: the alternatives are both worse. Governing
  /// a period by its first day silently drops the tail of a mid-week schedule
  /// change — days that were expected simply vanish from accounting. Charging
  /// the full target over a clipped span manufactures a failure the user could
  /// not have avoided, which the spec forbids. Clipping with proration keeps
  /// every day accounted and every target reachable.
  ///
  /// Clipping is against schedule validity only, never against [range] — a
  /// caller asking about two days in the middle of a week must still see that
  /// week's whole target, or the home screen would understate it.
  ///
  /// A period drops out entirely when every day in its effective span is
  /// paused, and a daily occurrence drops out when its date is paused: paused
  /// time leaves the denominator rather than counting against the user.
  List<ExpectedOccurrence> occurrencesIn({
    required String commitmentId,
    required List<CommitmentSchedule> schedules,
    required List<PausePeriod> pauses,
    required CivilDateRange range,
  }) {
    final out = <ExpectedOccurrence>[];
    final seenPeriods = <String>{};

    for (final date in range.dates) {
      final schedule = scheduleOn(schedules, date);
      if (schedule == null) continue;

      final frequency = schedule.frequency;

      if (!frequency.isPeriodScoped) {
        if (_isPaused(pauses, date)) continue;
        if (!_dailyShapeMatches(schedule, date)) continue;
        out.add(DailyOccurrence(
          commitmentId: commitmentId,
          date: date,
          target: frequency.target,
        ));
        continue;
      }

      final scope = frequency.scope;
      final period = calendar.periodContaining(scope, date);

      // Keyed by schedule version too, so a straddling period yields one
      // clipped occurrence per version rather than one blended occurrence.
      if (!seenPeriods.add('${scope.name}:${period.start.iso}:${schedule.id}')) {
        continue;
      }

      final effective = _clipToSchedule(period, schedule);
      if (effective.dates.every((day) => _isPaused(pauses, day))) continue;

      out.add(PeriodOccurrence(
        commitmentId: commitmentId,
        scope: scope,
        period: period,
        effective: effective,
        target: _prorate(frequency.target, effective, period),
      ));
    }

    return out;
  }

  /// Narrows a period to the days [schedule] actually governs.
  CivilDateRange _clipToSchedule(
    CivilDateRange period,
    CommitmentSchedule schedule,
  ) {
    final start = schedule.effectiveFrom > period.start
        ? schedule.effectiveFrom
        : period.start;
    final to = schedule.effectiveTo;
    final end = (to != null && to < period.end) ? to : period.end;
    return CivilDateRange(start, end);
  }

  /// Scales a target down to a clipped span, never below 1 and never above the
  /// nominal target.
  int _prorate(int target, CivilDateRange effective, CivilDateRange period) {
    if (effective == period) return target;
    final scaled =
        (target * effective.lengthInDays / period.lengthInDays).round();
    return scaled.clamp(1, target);
  }
}
