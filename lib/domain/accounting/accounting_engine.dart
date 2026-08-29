import '../analytics/scoring.dart';
import '../model/pause_period.dart';
import '../model/schedule.dart';
import '../model/tracking_event.dart';
import '../recurrence/expected_occurrence.dart';
import '../recurrence/recurrence_engine.dart';
import '../time/accounting_calendar.dart';
import '../time/civil_date.dart';
import '../time/clock.dart';
import 'occurrence_status.dart';
import 'resolved_occurrence.dart';

/// Applies what actually happened to what was expected.
///
/// Pure: every time-dependent decision comes from the injected [Clock] via
/// [calendar], so the same inputs always produce the same statuses.
class AccountingEngine {
  const AccountingEngine({
    required this.calendar,
    required this.recurrence,
    this.weights = ScoringWeights.standard,
  });

  final AccountingCalendar calendar;
  final RecurrenceEngine recurrence;
  final ScoringWeights weights;

  /// Resolves one occurrence against the events recorded for its commitment.
  ///
  /// The ordering of the checks is the specification, not an implementation
  /// detail:
  ///
  /// 1. An explicit skip wins outright, but only for a [DailyOccurrence]. The
  ///    user said "not this one", and that must never decay into a miss no
  ///    matter what else is true. A [PeriodOccurrence] deliberately ignores
  ///    skips — see below.
  /// 2. A met target is [done] immediately, even mid-period — hitting 4/4 on
  ///    Thursday is a finished week, not a pending one.
  /// 3. An open window is [pending]. Nothing becomes [missed] before it closes,
  ///    which is what stops today, and every future day, from counting against
  ///    the user.
  /// 4. Only then, on a closed window, does shortfall become [partial] or
  ///    [missed].
  ResolvedOccurrence resolve({
    required ExpectedOccurrence occurrence,
    required List<TrackingEvent> events,
    required Clock clock,
  }) {
    final span = occurrence.span;
    final relevant = events
        .where((e) => e.commitmentId == occurrence.commitmentId)
        .where((e) => span.contains(e.accountingDate))
        .toList();

    final note = relevant
        .where((e) => e.note != null && e.note!.isNotEmpty)
        .map((e) => e.note)
        .lastOrNull;

    // A skip is a statement about one day, so it can only settle one day.
    //
    // A period is scored over its target, not its days: "3x/week" asks for
    // three days out of seven and has no opinion about which. Letting a
    // skipped Wednesday mark the whole week skipped dropped an entire week out
    // of the denominator and discarded completions already recorded in it —
    // two done days scoring as `0 / 3`. Found on device, where a generated
    // year finally produced the combination; every earlier skip test was
    // daily, which is the only shape this check was written for.
    if (occurrence is DailyOccurrence &&
        relevant.any((e) => e.kind == TrackingKind.skipped)) {
      return resolutionOf(
        occurrence: occurrence,
        status: OccurrenceStatus.skipped,
        completed: 0,
        weights: weights,
        note: note,
      );
    }

    final completed = relevant
        .where((e) => e.kind == TrackingKind.done)
        .fold(0, (sum, e) => sum + e.count);
    final attempted =
        completed > 0 || relevant.any((e) => e.kind == TrackingKind.partial);

    if (completed >= occurrence.target) {
      return resolutionOf(
        occurrence: occurrence,
        status: OccurrenceStatus.done,
        completed: completed,
        weights: weights,
        note: note,
      );
    }

    final isClosed = occurrence is PeriodOccurrence
        ? calendar.isPeriodClosed(occurrence.effective, clock)
        : calendar.isDayClosed(span.start, clock);

    if (!isClosed) {
      return resolutionOf(
        occurrence: occurrence,
        status: OccurrenceStatus.pending,
        completed: completed,
        weights: weights,
        note: note,
      );
    }

    return resolutionOf(
      occurrence: occurrence,
      status: attempted ? OccurrenceStatus.partial : OccurrenceStatus.missed,
      completed: completed,
      weights: weights,
      note: note,
    );
  }

  /// Resolves every occurrence a commitment had in [range].
  List<ResolvedOccurrence> resolveRange({
    required String commitmentId,
    required List<CommitmentSchedule> schedules,
    required List<PausePeriod> pauses,
    required List<TrackingEvent> events,
    required CivilDateRange range,
    required Clock clock,
  }) {
    final expected = recurrence.occurrencesIn(
      commitmentId: commitmentId,
      schedules: schedules,
      pauses: pauses,
      range: range,
    );
    return [
      for (final o in expected)
        resolve(occurrence: o, events: events, clock: clock),
    ];
  }

  /// The status of a single calendar date, including the exclusions the
  /// recurrence engine expresses by silence.
  ///
  /// [resolveRange] omits paused and unscheduled dates entirely, which is right
  /// for analytics but wrong for a calendar cell that still has to render
  /// something. This distinguishes the two.
  OccurrenceStatus statusOnDate({
    required String commitmentId,
    required List<CommitmentSchedule> schedules,
    required List<PausePeriod> pauses,
    required List<TrackingEvent> events,
    required CivilDate date,
    required Clock clock,
  }) {
    if (pauses.any((p) => p.covers(date))) return OccurrenceStatus.paused;

    final occurrences = recurrence.occurrencesIn(
      commitmentId: commitmentId,
      schedules: schedules,
      pauses: pauses,
      range: CivilDateRange(date, date),
    );
    if (occurrences.isEmpty) return OccurrenceStatus.notScheduled;

    return resolve(
      occurrence: occurrences.first,
      events: events,
      clock: clock,
    ).status;
  }
}
