import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riyaz/app/formatting.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/app/shell.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/accounting/resolved_occurrence.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/recurrence/expected_occurrence.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/features/home/today_controller.dart';
import 'package:riyaz/features/home/widgets/status_indicator.dart';

part 'week_grid.g.dart';

/// One commitment's week.
///
/// Every row keeps the same seven columns, daily and period alike, so each one
/// lines up with the M–T–W header above it. A period row used to collapse into
/// a single chip, which left it spanning the grid at no particular column and
/// made the whole table read as a rendering fault.
///
/// The original worry was real and still holds: drawing seven *status* cells
/// for a 4x/week target would say each day was expected, which is the precise
/// misconception the accounting model exists to prevent. So a period row does
/// not draw statuses. It draws a small dot on the days a completion actually
/// landed — a record of where the week's work fell, after the fact, carrying
/// no claim that any of those days was owed. The two marks are deliberately
/// different shapes, and the legend names them separately.
class WeekRow {
  const WeekRow({
    required this.commitment,
    required this.byDay,
    required this.period,
  });

  final Commitment commitment;
  final Map<int, ResolvedOccurrence> byDay;
  final ResolvedOccurrence? period;

  bool get isPeriod => period != null;
}

class WeekGridData {
  const WeekGridData({required this.week, required this.rows});

  final CivilDateRange week;
  final List<WeekRow> rows;
}

@riverpod
class VisibleWeek extends _$VisibleWeek {
  @override
  CivilDate build() =>
      ref.watch(accountingCalendarProvider).startOfWeek(ref.watch(todayProvider));

  void previous() => state = state.plusDays(-7);

  void next() {
    final limit = ref
        .read(accountingCalendarProvider)
        .startOfWeek(ref.read(todayProvider));
    final candidate = state.plusDays(7);
    state = candidate > limit ? limit : candidate;
  }
}

@riverpod
Stream<WeekGridData> weekGrid(Ref ref, CivilDate weekStart) {
  final week = CivilDateRange(weekStart, weekStart.plusDays(6));

  return ref.watch(resolutionServiceProvider).watch(week).map((history) {
    final rows = <WeekRow>[];

    for (final commitment in history.commitments) {
      if (commitment.state == CommitmentState.archived) continue;

      final resolved = history.forCommitment(commitment.id);
      if (resolved.isEmpty) continue;

      final byDay = <int, ResolvedOccurrence>{};
      ResolvedOccurrence? period;

      for (final r in resolved) {
        if (r.occurrence is PeriodOccurrence) {
          period = r;
        } else {
          byDay[r.occurrence.span.start.epochDay] = r;
        }
      }

      rows.add(WeekRow(
        commitment: commitment,
        byDay: byDay,
        period: period,
      ));
    }

    return WeekGridData(week: week, rows: rows);
  });
}

class WeekGrid extends ConsumerWidget {
  const WeekGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final weekStart = ref.watch(visibleWeekProvider);
    final today = ref.watch(todayProvider);
    final calendar = ref.watch(accountingCalendarProvider);
    final data = ref.watch(weekGridProvider(weekStart));
    final atLatest = weekStart >= calendar.startOfWeek(today);

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: ref.read(visibleWeekProvider.notifier).previous,
              icon: const Icon(Icons.chevron_left_rounded),
              tooltip: 'Previous week',
            ),
            Expanded(
              child: Text(
                '${dayLabel(weekStart)} – ${dayLabel(weekStart.plusDays(6))}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              onPressed:
                  atLatest ? null : ref.read(visibleWeekProvider.notifier).next,
              icon: const Icon(Icons.chevron_right_rounded),
              tooltip: 'Next week',
            ),
            // Only for a week that is over. A review states a final result,
            // and the week in progress does not have one yet — the same rule
            // that stops the review screen ever looking at the current week.
            IconButton(
              onPressed: atLatest
                  ? null
                  : () => context.push('/review/${weekStart.iso}'),
              icon: const Icon(Icons.summarize_outlined),
              tooltip: 'Review this week',
            ),
          ],
        ),
        Expanded(
          child: data.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (grid) => grid.rows.isEmpty
                ? const Center(child: Text('Nothing tracked this week.'))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    children: [
                      _DayHeader(week: grid.week),
                      const Divider(),
                      for (final row in grid.rows)
                        _Row(row: row, week: grid.week, today: today),
                      const SizedBox(height: 16),
                      const _WeekLegend(),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.week});

  final CivilDateRange week;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const SizedBox(width: 108),
        for (final date in week.dates)
          Expanded(
            child: Center(
              child: Text(
                weekdayName(date).substring(0, 1),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.row, required this.week, required this.today});

  final WeekRow row;
  final CivilDateRange week;
  final CivilDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final period = row.period;
    final credited = period?.creditedDays.toSet() ?? const <CivilDate>{};
    final met = period != null && period.completed >= period.target;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  row.commitment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                // The tally sits under the name rather than in a chip out in
                // the grid, where it had no column of its own to occupy.
                if (row.isPeriod)
                  Text(
                    '${row.period!.completed} of ${row.period!.target}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: met
                          ? context.statusColors.done
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          for (final date in week.dates)
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: date > today
                      ? null
                      : () {
                          ref.read(selectedDateProvider.notifier).goTo(date);
                          ref.read(selectedTabProvider.notifier).go(0);
                        },
                  child: row.isPeriod
                      ? _TargetCell(
                          credited: credited.contains(date),
                          past: date <= today,
                        )
                      : StatusIndicator(
                          status: row.byDay[date.epochDay]?.status ??
                              OccurrenceStatus.notScheduled,
                          size: 20,
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A day inside a period commitment's week.
///
/// Deliberately not a [StatusIndicator]. A filled dot here means "a completion
/// landed on this day", never "this day was expected and met" — the week is
/// the unit that gets judged, and no day inside it is owed anything on its
/// own. Small and quiet so it cannot be mistaken for the status vocabulary
/// running down the daily rows above it.
class _TargetCell extends StatelessWidget {
  const _TargetCell({required this.credited, required this.past});

  /// A completion was recorded on this day.
  final bool credited;

  /// The day has already happened.
  final bool past;

  @override
  Widget build(BuildContext context) {
    // The empty dot is a column marker, not a state — what carries meaning is
    // the presence of the filled one. That is what licenses `futureRing`
    // here, the palette's one openly decorative value: nothing is being said
    // by it, so it owes no contrast floor. A day that has not happened yet
    // gets no mark at all.
    if (!credited) {
      return Semantics(
        // Its own node. A cell for a day still to come paints nothing, and an
        // empty annotation gets absorbed into the row above it — which read
        // out as "Gym, 0 of 4, Not yet, Not yet" in one breath.
        container: true,
        label: past ? 'Nothing counted' : 'Not yet',
        child: SizedBox(
          width: 20,
          height: 20,
          child: past
              ? Center(
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.palette.futureRing,
                    ),
                  ),
                )
              : null,
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'Counted toward the target',
      child: SizedBox(
        width: 20,
        height: 20,
        child: Center(
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.statusColors.done,
            ),
          ),
        ),
      ),
    );
  }
}

/// Names both vocabularies the grid uses.
///
/// The target dot is the reason this exists. A small sage dot appearing in a
/// row of ticks and crosses is unreadable until something says what it counts,
/// and the distinction it draws — a day a completion landed on, versus a day
/// that was expected and met — is the one the whole period model rests on.
///
/// Built from `StatusIndicator` and `_TargetCell` themselves rather than from
/// swatches that imitate them. The month legend learned that the hard way: it
/// built its own circles out of `scheme.*`, agreed with the grid by
/// coincidence, and started teaching the wrong thing the moment the grid
/// changed underneath it.
class _WeekLegend extends StatelessWidget {
  const _WeekLegend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget entry(Widget mark, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(child: mark),
            const SizedBox(width: 6),
            Text(label, style: theme.textTheme.labelSmall),
          ],
        );

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        entry(
          const StatusIndicator(status: OccurrenceStatus.done, size: 14),
          'Done',
        ),
        entry(
          const StatusIndicator(status: OccurrenceStatus.partial, size: 14),
          'Partial',
        ),
        entry(
          const StatusIndicator(status: OccurrenceStatus.missed, size: 14),
          'Missed',
        ),
        entry(
          const StatusIndicator(status: OccurrenceStatus.skipped, size: 14),
          'Skipped',
        ),
        entry(
          const StatusIndicator(status: OccurrenceStatus.pending, size: 14),
          'Not yet',
        ),
        entry(
          const _TargetCell(credited: true, past: true),
          'Counted toward a target',
        ),
      ],
    );
  }
}
