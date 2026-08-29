import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riyaz/app/formatting.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/app/shell.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/domain/analytics/day_band.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/features/home/today_controller.dart';

import 'history_controller.dart';
import 'week_grid.dart';
import 'widgets/calendar_cell.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  bool _weekMode = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: Column(
        children: [
          // In the body rather than AppBar.actions: a two-segment button plus
          // a title overflows a phone-width app bar, and it overflows much
          // harder once the user turns text scaling up.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Month')),
                  ButtonSegment(value: true, label: Text('Week')),
                ],
                selected: {_weekMode},
                onSelectionChanged: (s) =>
                    setState(() => _weekMode = s.first),
              ),
            ),
          ),
          Expanded(
            child: _weekMode ? const WeekGrid() : const _MonthCalendar(),
          ),
        ],
      ),
    );
  }
}

class _MonthCalendar extends ConsumerWidget {
  const _MonthCalendar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final month = ref.watch(visibleMonthProvider);
    final today = ref.watch(todayProvider);
    final calendar = ref.watch(accountingCalendarProvider);
    final data = ref.watch(calendarMonthProvider(month));

    final weekStart = calendar.weekStartsOn;
    final headers = [
      for (var i = 0; i < 7; i++)
        weekdayName(CivilDate.fromEpochDay(
          // Any known Monday, offset to the configured first weekday.
          const CivilDate(2026, 8, 24).epochDay + ((weekStart - 1 + i) % 7),
        )).substring(0, 1),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: ref.read(visibleMonthProvider.notifier).previous,
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Previous month',
              ),
              Expanded(
                child: Text(
                  '${shortMonth(month)} ${month.year}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                onPressed: month >= today.startOfMonth
                    ? null
                    : ref.read(visibleMonthProvider.notifier).next,
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: 'Next month',
              ),
            ],
          ),
        ),
        Expanded(
          child: data.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (month) => ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: [
                _MonthSummary(month: month),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final h in headers)
                      Expanded(
                        child: Center(
                          child: Text(
                            h,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    childAspectRatio: 1,
                  ),
                  itemCount: month.days.length,
                  itemBuilder: (context, i) {
                    final day = month.days[i];
                    return CalendarCell(
                      day: day,
                      isToday: day.date == today,
                      onTap: day.date > today
                          ? null
                          : () => _openDay(context, ref, day.date),
                    );
                  },
                ),
                const SizedBox(height: 16),
                const _Legend(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Sends the user to the tracking tab on that date rather than building a
  /// second editing surface. The today screen already handles any date.
  void _openDay(BuildContext context, WidgetRef ref, CivilDate date) {
    ref.read(selectedDateProvider.notifier).goTo(date);
    ref.read(selectedTabProvider.notifier).go(0);
  }
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.month});

  final CalendarMonth month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = month.summary;

    // A column, not one wide row: the headline plus four labelled counts do
    // not fit across a phone, and they fit far worse once text scaling is
    // turned up. Each count is Expanded so the row divides whatever width
    // exists rather than demanding a fixed amount.
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  s.percent == null ? '—' : '${s.percent}%',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'consistency',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Count(label: 'Done', value: s.done),
                _Count(label: 'Partial', value: s.partial),
                _Count(label: 'Missed', value: s.missed),
                _Count(label: 'Skipped', value: s.skipped),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: theme.textTheme.titleMedium),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bands = context.bandColors;

    // Drawn from the same styles the grid uses, ring weight included. This
    // used to build its own swatches out of `scheme.*`, which made it a second
    // definition of the band vocabulary that merely happened to agree — and
    // stopped agreeing the moment weak and empty days started differing by
    // ring weight. A legend that contradicts the thing it explains is worse
    // than no legend.
    Widget swatch(DayBand band, String label) {
      final style = bands.forBand(band);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: style.fill,
              border: Border.all(color: style.border, width: style.width),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      );
    }

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        swatch(DayBand.strong, 'Strong'),
        swatch(DayBand.partial, 'Partial'),
        swatch(DayBand.weak, 'Weak'),
        swatch(DayBand.none, 'Nothing tracked'),
        swatch(DayBand.future, 'Not yet'),
      ],
    );
  }
}
