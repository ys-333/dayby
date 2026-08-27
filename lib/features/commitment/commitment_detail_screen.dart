import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riyaz/app/formatting.dart';
import 'package:riyaz/domain/analytics/consistency_summary.dart';
import 'package:riyaz/features/home/widgets/status_indicator.dart';

import 'commitment_detail_controller.dart';
import 'widgets/trend_chart.dart';

class CommitmentDetailScreen extends ConsumerWidget {
  const CommitmentDetailScreen({required this.commitmentId, super.key});

  final String commitmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(commitmentDetailProvider(commitmentId));

    return Scaffold(
      appBar: AppBar(title: Text(detail.value?.commitment.name ?? '')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) => data == null
            ? const Center(child: Text('This commitment no longer exists.'))
            : _Body(detail: data),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.detail});

  final CommitmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final streaks = detail.streaks;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Row(
          children: [
            if (detail.commitment.icon != null) ...[
              Text(
                detail.commitment.icon!,
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.commitment.name,
                    style: theme.textTheme.titleLarge,
                  ),
                  Text(
                    'Started ${dayLabel(detail.commitment.startedOn)}, '
                    '${detail.commitment.startedOn.year}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SectionTitle('Momentum'),
        Row(
          children: [
            _Stat(
              label: 'Current streak',
              value: '${streaks.current}',
              unit: streaks.current == 1 ? 'day' : 'days',
            ),
            _Stat(
              label: 'Longest',
              value: '${streaks.longest}',
              unit: streaks.longest == 1 ? 'day' : 'days',
            ),
            _Stat(
              label: 'Avg recovery',
              // Null until a lapse has actually been recovered from. Showing
              // "0 days" would claim a resilience that has not been shown.
              value: streaks.averageRecoveryDays == null
                  ? '—'
                  : streaks.averageRecoveryDays!.toStringAsFixed(1),
              unit: streaks.averageRecoveryDays == null ? '' : 'days',
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _SectionTitle('Consistency'),
        Row(
          children: [
            _Stat.percent('This week', detail.thisWeek),
            _Stat.percent('This month', detail.thisMonth),
            _Stat.percent('90 days', detail.last90),
            _Stat.percent('This year', detail.thisYear),
          ],
        ),
        const SizedBox(height: 24),
        const _SectionTitle('Performance'),
        Row(
          children: [
            _Stat(label: 'Done', value: '${detail.thisYear.done}'),
            _Stat(label: 'Partial', value: '${detail.thisYear.partial}'),
            _Stat(label: 'Missed', value: '${detail.thisYear.missed}'),
            _Stat(label: 'Skipped', value: '${detail.thisYear.skipped}'),
          ],
        ),
        const SizedBox(height: 24),
        const _SectionTitle('Rolling 7-day consistency'),
        TrendChart(points: detail.trend),
        const SizedBox(height: 24),
        const _SectionTitle('Recent'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final r in detail.recent)
              Tooltip(
                message: '${r.occurrence.span.end.iso}: ${r.status.name}',
                child: StatusIndicator(status: r.status, size: 18),
              ),
          ],
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.1,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.unit});

  /// Renders a summary as a percentage, or an em dash when nothing is eligible.
  factory _Stat.percent(String label, ConsistencySummary summary) => _Stat(
        label: label,
        value: summary.percent == null ? '—' : '${summary.percent}%',
      );

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (unit != null && unit!.isNotEmpty)
            Text(unit!, style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
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
