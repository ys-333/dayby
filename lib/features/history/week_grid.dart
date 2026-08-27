import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riyaz/app/formatting.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/app/shell.dart';
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
/// Daily and period commitments are deliberately different shapes here, not a
/// uniform seven cells. Drawing seven cells for a 4x/week target would imply
/// each day was expected, which is the exact misconception the accounting model
/// exists to prevent.
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            child: Text(
              row.commitment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (row.isPeriod)
            // One progress chip for the whole row: the week is the unit, and
            // no individual day inside it was ever expected on its own.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    '${row.period!.completed} / ${row.period!.target} this week',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
            )
          else
            for (final date in week.dates)
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: date > today
                        ? null
                        : () {
                            ref
                                .read(selectedDateProvider.notifier)
                                .goTo(date);
                            ref.read(selectedTabProvider.notifier).go(0);
                          },
                    child: StatusIndicator(
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
