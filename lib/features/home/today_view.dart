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

  /// Null when there is nothing to do — an empty day is not 0% done.
  double? get progress => total == 0 ? null : completed / total;

  int? get percent => progress == null ? null : (progress! * 100).round();

  bool get isEmpty => items.isEmpty;
}
