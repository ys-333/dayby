import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/accounting/resolved_occurrence.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/recurrence/expected_occurrence.dart';
import 'package:riyaz/domain/time/civil_date.dart';

/// One row on the today screen.
class TodayItem {
  const TodayItem({required this.commitment, required this.resolved});

  final Commitment commitment;
  final ResolvedOccurrence resolved;

  OccurrenceStatus get status => resolved.status;

  /// The note attached to this occurrence, if the user wrote one.
  String? get note => resolved.note;
  int get completed => resolved.completed;
  int get target => resolved.target;

  /// True for week/month targets, which must read visibly differently from
  /// daily ones — "2 / 4 this week" is not a half-finished day.
  bool get isPeriod => resolved.occurrence is PeriodOccurrence;

  /// Whether tapping should add one more rather than complete outright.
  bool get isCountable => isPeriod || target > 1;

  /// Finished: the target for this occurrence is met.
  bool get isDone => status == OccurrenceStatus.done;

  /// Still open and still actionable today.
  bool get isPending => status == OccurrenceStatus.pending;

  /// Out of the reckoning — shown, never scored, and never struck through.
  bool get isExcluded =>
      status == OccurrenceStatus.skipped || status == OccurrenceStatus.paused;

  /// The word a row shows under its name, or null when the status is one the
  /// mark already says.
  ///
  /// Pending and done need no caption: an empty ring and a filled tick are
  /// unambiguous, and a column of "Not done yet" under every untouched row is
  /// the noise the redesign set out to remove. Everything else is a state the
  /// user cannot infer from the mark alone, so it stays legible as words.
  String? get statusCaption => switch (status) {
        OccurrenceStatus.pending => null,
        OccurrenceStatus.done => null,
        OccurrenceStatus.partial => 'Partial',
        OccurrenceStatus.missed => 'Missed',
        OccurrenceStatus.skipped => 'Skipped',
        OccurrenceStatus.paused => 'Paused',
        OccurrenceStatus.notScheduled => 'Not scheduled',
      };

  /// The bare noun for this row's period: "week", "month".
  String? get periodNoun => switch (periodLabel) {
        'this week' => 'week',
        'this month' => 'month',
        _ => null,
      };

  /// The scope word for a period row: "this week", "this month".
  String? get periodLabel {
    final occurrence = resolved.occurrence;
    if (occurrence is! PeriodOccurrence) return null;
    return switch (occurrence.scope.name) {
      'weekly' => 'this week',
      'monthly' => 'this month',
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is TodayItem &&
      other.commitment.id == commitment.id &&
      other.status == status &&
      other.completed == completed;

  @override
  int get hashCode => Object.hash(commitment.id, status, completed);
}

/// Everything the today screen renders.
class TodayView {
  const TodayView({required this.date, required this.items});

  static const TodayView empty = TodayView(
    date: CivilDate(1970, 1, 1),
    items: [],
  );

  final CivilDate date;
  final List<TodayItem> items;

  /// Rows that count toward today's progress. Skipped and paused rows are
  /// shown but excluded, matching how they are excluded from consistency.
  List<TodayItem> get countable =>
      items.where((i) => i.status != OccurrenceStatus.skipped).toList();

  int get completed =>
      countable.where((i) => i.status == OccurrenceStatus.done).length;

  int get total => countable.length;

  /// Rows the day can be late on. Principle 3: a daily commitment and a
  /// period target never share a group, because only one of them can be
  /// behind at four in the afternoon.
  List<TodayItem> get daily => items.where((i) => !i.isPeriod).toList();

  /// Week and month targets, scored over their period rather than this day.
  List<TodayItem> get period => items.where((i) => i.isPeriod).toList();

  /// Daily rows still open. Skipped, paused and already-recorded rows are not
  /// "left" — nothing about them is waiting on the user.
  int get dailyLeft => daily.where((i) => i.isPending).length;

  /// Daily rows that count toward the day: everything but skips and pauses.
  int get dailyExpected => daily.where((i) => !i.isExcluded).length;

  int get dailyDone => daily.where((i) => i.isDone).length;

  /// Period targets already met, grouped by their period noun — the material
  /// for the reassurance line at the foot of the list.
  Map<String, List<TodayItem>> get metPeriodsByNoun {
    final byNoun = <String, List<TodayItem>>{};
    for (final item in period) {
      if (!item.isDone) continue;
      final noun = item.periodNoun;
      if (noun == null) continue;
      byNoun.putIfAbsent(noun, () => []).add(item);
    }
    return byNoun;
  }

  /// Null when there is nothing to do — an empty day is not 0% done.
  double? get progress => total == 0 ? null : completed / total;

  int? get percent => progress == null ? null : (progress! * 100).round();

  bool get isEmpty => items.isEmpty;
}
