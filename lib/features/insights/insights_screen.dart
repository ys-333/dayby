import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riyaz/app/formatting.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/domain/analytics/consistency_summary.dart';
import 'package:riyaz/domain/insights/insight.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/features/commitment/widgets/trend_chart.dart';

import 'insights_controller.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(insightsDataProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) => _Body(data: data),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data});

  final InsightsData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const _Section('Consistency'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              data.last90.percent == null ? '—' : '${data.last90.percent}%',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'last 90 days',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 20,
          children: [
            _Count('Done', data.last90.done),
            _Count('Partial', data.last90.partial),
            _Count('Missed', data.last90.missed),
            _Count('Skipped', data.last90.skipped),
          ],
        ),
        const SizedBox(height: 24),
        const _Section('Rolling 7-day trend'),
        TrendChart(points: data.trend),
        const SizedBox(height: 24),
        const _Section('Momentum'),
        Row(
          children: [
            _Stat('Current streak', '${data.streaks.current}'),
            _Stat('Longest', '${data.streaks.longest}'),
            _Stat(
              'Avg run',
              data.streaks.averageStreak == 0
                  ? '—'
                  : data.streaks.averageStreak.toStringAsFixed(1),
            ),
            _Stat(
              'Avg recovery',
              data.streaks.averageRecoveryDays == null
                  ? '—'
                  : data.streaks.averageRecoveryDays!.toStringAsFixed(1),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _Section('${today.year}'),
        _YearBars(months: data.months),
        const SizedBox(height: 24),
        const _Section('Patterns'),
        if (!data.result.hasEnoughData)
          _NotEnoughData(result: data.result)
        else if (data.result.insights.isEmpty)
          Text(
            'Nothing stands out yet. That is a fine place to be.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        for (final insight in data.result.insights)
          _InsightCard(insight: insight),
      ],
    );
  }
}

/// The honest empty state. "No patterns found" and "not enough data to look"
/// are different claims, and conflating them teaches the user to distrust every
/// other number on the screen.
class _NotEnoughData extends StatelessWidget {
  const _NotEnoughData({required this.result});

  final InsightsResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining =
        result.requiredObservations - result.eligibleObservations;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Not enough data yet', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              'Keep tracking for a little longer. About $remaining more '
              'tracked days and patterns start to mean something.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWarning = insight.kind == InsightKind.load;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isWarning ? theme.colorScheme.errorContainer : null,
      child: ListTile(
        leading: Icon(
          switch (insight.kind) {
            InsightKind.momentum => Icons.trending_up_rounded,
            InsightKind.recovery => Icons.replay_rounded,
            InsightKind.dayOfWeek => Icons.today_rounded,
            InsightKind.trend => Icons.show_chart_rounded,
            InsightKind.load => Icons.warning_amber_rounded,
          },
          color: isWarning ? theme.colorScheme.onErrorContainer : null,
        ),
        title: Text(insight.headline),
        subtitle: insight.detail == null ? null : Text(insight.detail!),
      ),
    );
  }
}

class _YearBars extends StatelessWidget {
  const _YearBars({required this.months});

  final Map<CivilDate, ConsistencySummary> months;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (months.isEmpty) {
      return Text(
        'No months to compare yet.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      children: [
        for (final entry in months.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                // Constrained rather than fixed: a hard 36dp cannot hold
                // "Jul" once the user turns text scaling up, and the row
                // overflows instead of the label shrinking.
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 36),
                  child: Text(
                    shortMonth(entry.key),
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: entry.value.consistency ?? 0,
                      minHeight: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 40),
                  child: Text(
                    entry.value.percent == null
                        ? '—'
                        : '${entry.value.percent}%',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.1,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value);

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value', style: theme.textTheme.titleMedium),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
