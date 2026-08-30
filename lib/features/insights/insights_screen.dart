import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riyaz/app/formatting.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/app/theme/tokens.dart';
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
        const SizedBox(height: Insets.titleGap * 2),
        // The denominator, said out loud. A percentage with no stated base is
        // a number the reader can neither argue with nor learn from — and this
        // one has a base most people would guess wrong, because skips, pauses,
        // unscheduled days and anything still pending are all already out of
        // it. "Yours to make" is the whole claim in three words.
        Text(
          data.last90.eligible == 0
              ? 'Nothing has settled in the last 90 days yet'
              : 'Of ${data.last90.eligible} occurrences that were yours '
                  'to make',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Insets.rowTrailingGap),
        Wrap(
          spacing: 20,
          runSpacing: Insets.rowTrailingGap,
          children: [
            _Count('Done', data.last90.done),
            _Count('Partial', data.last90.partial),
            _Count('Missed', data.last90.missed),
            // Dimmed and captioned, because it is not a fourth outcome. A skip
            // is a decision the user made and it leaves the denominator
            // entirely — rendering it in the same weight as Missed invites
            // exactly the reading the accounting model exists to prevent.
            _Count('Skipped', data.last90.skipped, excluded: true),
          ],
        ),
        const SizedBox(height: 24),
        const _Section('Rolling 7-day trend'),
        TrendChart(points: data.trend),
        const SizedBox(height: 24),
        const _Section('Momentum'),
        // **The current streak is not here, and that is the point.**
        // `CLAUDE.md`: "Streaks are shown but are deliberately not the
        // headline metric — long-run consistency and recovery time are." It
        // used to lead this row as the largest number on the screen, which is
        // the ordinary habit-tracker failure: a counter that only ever goes to
        // zero, and takes the user's motivation with it. It is a footnote now,
        // in a sentence, below the three figures that actually describe how
        // someone practises.
        //
        // Wording matches the commitment detail screen exactly. The two
        // screens report the same three numbers and used to call them
        // different things.
        Row(
          spacing: Insets.rowTrailingGap,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Stat(
              'A typical run',
              data.streaks.averageStreak == 0
                  ? '—'
                  : data.streaks.averageStreak.toStringAsFixed(1),
              unit: data.streaks.averageStreak == 0 ? null : 'days',
            ),
            const _Rule(),
            _Stat(
              'Your best run',
              '${data.streaks.longest}',
              unit: data.streaks.longest == 1 ? 'day' : 'days',
            ),
            const _Rule(),
            _Stat(
              'To come back',
              data.streaks.averageRecoveryDays == null
                  ? '—'
                  : data.streaks.averageRecoveryDays!.toStringAsFixed(1),
              unit: data.streaks.averageRecoveryDays == null ? null : 'days',
            ),
          ],
        ),
        const SizedBox(height: Insets.rowTrailingGap),
        Text(
          switch (data.streaks.current) {
            0 => 'Not on a run right now.',
            1 => 'Currently on day 1.',
            final n => 'Currently on day $n.',
          },
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
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

/// One observation, styled as an observation.
///
/// The load insight used to get [ColorScheme.errorContainer] and a warning
/// triangle, which made "you have eleven daily commitments" arrive in the
/// livery of a form you filled in wrong. It is advice — the user chose those
/// eleven — and every other card on the screen is phrased descriptively for
/// exactly the reason this one should be too. [Insight] carries no valence
/// field on purpose; giving one kind an alarm treatment reintroduces the
/// verdict the model went out of its way not to make.
///
/// So every card takes the same surface. Only the icon distinguishes them, and
/// only recovery is tinted, because coming back quickly is the thing this app
/// argues matters most and the one number it is willing to be pleased about.
class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
          switch (insight.kind) {
            InsightKind.momentum => Icons.trending_up_rounded,
            InsightKind.recovery => Icons.replay_rounded,
            InsightKind.dayOfWeek => Icons.today_rounded,
            InsightKind.trend => Icons.show_chart_rounded,
            // Stacked layers, not a warning triangle: the observation is that
            // a lot is stacked up, which is a quantity, not a hazard.
            InsightKind.load => Icons.layers_rounded,
          },
          color: insight.kind == InsightKind.recovery
              ? context.statusColors.done
              : theme.colorScheme.onSurfaceVariant,
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
  const _Stat(this.label, this.value, {this.unit});

  final String label;
  final String value;

  /// "days". Null when the figure is an em dash, because "— days" is worse
  /// than "—".
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (unit != null)
            Text(unit!, style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
            )),
          const SizedBox(height: Insets.titleGap),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

/// The hairline between two momentum figures.
///
/// They are three separate answers, not one row of numbers, and without a rule
/// between them the eye reads "2.0 9 3.2" as a sequence.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 34,
        margin: const EdgeInsets.only(top: Insets.titleGap * 2),
        color: context.palette.line,
      );
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value, {this.excluded = false});

  final String label;
  final int value;

  /// True for a tally that sits **outside** the score rather than inside it.
  ///
  /// It is recessive and it says so in words. Colour alone would not do the
  /// job here — that is the app's standing rule — and in any case the thing
  /// being communicated is not a status but a piece of arithmetic: this number
  /// was never in the denominator.
  final bool excluded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      label: excluded
          ? '$value $label, not counted toward consistency'
          : '$value $label',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: theme.textTheme.titleMedium?.copyWith(
              color: excluded ? muted : null,
            ),
          ),
          Text(
            excluded ? '$label, not counted' : label,
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}
