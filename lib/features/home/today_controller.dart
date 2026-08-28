import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/time/accounting_calendar.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/domain/time/clock.dart';

import 'package:riyaz/app/formatting.dart';
import 'package:riyaz/features/widget/widget_bridge.dart';
import 'package:riyaz/features/widget/widget_payload.dart';

import 'today_view.dart';

part 'today_controller.g.dart';

/// Live view of one accounting day.
///
/// Parameterised by date rather than pinned to today, so backfilling a previous
/// day reuses the whole screen instead of needing a parallel implementation.
@riverpod
Stream<TodayView> todayView(Ref ref, CivilDate date) {
  final repo = ref.watch(trackingRepositoryProvider);
  final calendar = ref.watch(accountingCalendarProvider);
  final recurrence = ref.watch(recurrenceEngineProvider);
  final accounting = ref.watch(accountingEngineProvider);
  final clock = ref.watch(clockProvider);

  // Period targets are judged over their whole week or month, so the snapshot
  // has to reach wider than the day being shown or a "2 / 4 this week" row
  // would only ever see today's single event.
  final month = calendar.periodContaining(PeriodScope.monthly, date);
  final week = calendar.periodContaining(PeriodScope.weekly, date);
  final range = CivilDateRange(
    week.start < month.start ? week.start : month.start,
    week.end > month.end ? week.end : month.end,
  );

  return repo.watch(range).map((snapshot) {
    final items = <TodayItem>[];

    for (final commitment in snapshot.commitments) {
      // Archived commitments keep their history but leave the daily list.
      if (commitment.state == CommitmentState.archived) continue;
      if (date < commitment.startedOn) continue;

      final occurrences = recurrence.occurrencesIn(
        commitmentId: commitment.id,
        schedules: snapshot.schedulesFor(commitment.id),
        pauses: snapshot.pausesFor(commitment.id),
        range: CivilDateRange(date, date),
      );
      if (occurrences.isEmpty) continue;

      items.add(TodayItem(
        commitment: commitment,
        resolved: accounting.resolve(
          occurrence: occurrences.first,
          events: snapshot.events,
          clock: clock,
        ),
      ));
    }

    return TodayView(date: date, items: items);
  });
}

/// Write actions for the tracking screens.
///
/// Every method returns the [UndoToken] that reverses it, so no caller can
/// perform an un-undoable write by accident.
@riverpod
TrackingActions trackingActions(Ref ref) => TrackingActions(
      repository: ref.watch(trackingRepositoryProvider),
      clock: ref.watch(clockProvider),
    );

class TrackingActions {
  const TrackingActions({required this.repository, required this.clock});

  final TrackingRepository repository;
  final Clock clock;

  Future<UndoToken> markDone(TodayItem item, CivilDate date) =>
      repository.record(
        commitmentId: item.commitment.id,
        date: date,
        kind: TrackingKind.done,
        nowUtc: clock.nowUtc(),
        label: '${item.commitment.name} marked done',
      );

  Future<UndoToken> increment(TodayItem item, CivilDate date) =>
      repository.record(
        commitmentId: item.commitment.id,
        date: date,
        kind: TrackingKind.done,
        nowUtc: clock.nowUtc(),
        label: '${item.commitment.name} +1',
      );

  Future<UndoToken> markPartial(TodayItem item, CivilDate date) =>
      repository.record(
        commitmentId: item.commitment.id,
        date: date,
        kind: TrackingKind.partial,
        nowUtc: clock.nowUtc(),
        label: '${item.commitment.name} marked partial',
      );

  Future<UndoToken> skip(TodayItem item, CivilDate date) => repository.record(
        commitmentId: item.commitment.id,
        date: date,
        kind: TrackingKind.skipped,
        nowUtc: clock.nowUtc(),
        label: '${item.commitment.name} skipped',
      );

  Future<UndoToken> clear(TodayItem item, CivilDate date) => repository.clear(
        commitmentId: item.commitment.id,
        date: date,
        label: '${item.commitment.name} cleared',
      );

  Future<void> undo(UndoToken token) => repository.undo(token);
}

/// The day the tracking screens are showing.
///
/// Defaults to today and moves backwards for backfill. Never past today —
/// recording the future is meaningless, and offering it invites the user to
/// pre-tick days they have not lived yet.
@riverpod
class SelectedDate extends _$SelectedDate {
  @override
  CivilDate build() => ref.watch(todayProvider);

  void goTo(CivilDate date) {
    final today = ref.read(todayProvider);
    state = date > today ? today : date;
  }

  void previousDay() => goTo(state.plusDays(-1));

  void nextDay() => goTo(state.plusDays(1));

  void returnToToday() => goTo(ref.read(todayProvider));
}

@Riverpod(keepAlive: true)
WidgetBridge widgetBridge(Ref ref) => const WidgetBridge();

/// Keeps the home-screen widget in step with today.
///
/// Watches only *today*, never the selected date — the widget always shows the
/// current day, and a user browsing back through history must not rewrite what
/// their launcher displays.
///
/// Listens rather than transforming a stream: Riverpod 3 removed the `.stream`
/// modifier, and this is a side effect on every new value rather than a value
/// of its own.
@Riverpod(keepAlive: true)
class WidgetSync extends _$WidgetSync {
  @override
  int build() {
    final today = ref.watch(todayProvider);
    final bridge = ref.watch(widgetBridgeProvider);

    ref.listen(todayViewProvider(today), (previous, next) {
      final view = next.value;
      if (view == null) return;
      bridge
          .push(WidgetPayload.fromView(view, fullDayLabel(view.date)))
          .then((pushed) {
        if (pushed) state = state + 1;
      });
    }, fireImmediately: true);

    return 0;
  }
}
