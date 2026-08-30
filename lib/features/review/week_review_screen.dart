import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riyaz/app/formatting.dart';
import 'package:riyaz/app/glyphs.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/app/theme/tokens.dart';
import 'package:riyaz/app/theme/type_roles.dart';

import 'week_review_controller.dart';

/// What the user sees when a week ends — spec §64.
///
/// A moment of closure, and the only screen in the app that delivers a
/// **final** number. Everywhere else is careful never to score a window still
/// open: the day headline counts down instead of grading, a period is never
/// late mid-week, today is not in any denominator. That restraint is what
/// earns this screen the right to say "78%" plainly. The week is over; the
/// figure cannot move.
///
/// It is still not a verdict on the person. Best and hardest are named as
/// descriptions of two commitments, never as praise or a reprimand, and the
/// screen closes on recovery rather than on the miss count.
class WeekReviewScreen extends ConsumerWidget {
  const WeekReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(lastClosedWeekProvider);
    final review = ref.watch(weekReviewProvider(week.start));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your week'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Close',
          onPressed: () => _dismiss(context, ref),
        ),
      ),
      body: review.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) => data.hasResult
            ? _Body(review: data)
            : const _NothingToReview(),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(
          Insets.rowH,
          0,
          Insets.rowH,
          Insets.rowH,
        ),
        child: FilledButton(
          onPressed: () => _dismiss(context, ref),
          child: const Text('Done'),
        ),
      ),
    );
  }

  Future<void> _dismiss(BuildContext context, WidgetRef ref) async {
    await ref.read(reviewActionsProvider).dismiss();
    if (context.mounted) Navigator.of(context).maybePop();
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.review});

  final WeekReview review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final summary = review.summary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Insets.rowH,
        Insets.titleGap * 4,
        Insets.rowH,
        Insets.xl,
      ),
      children: [
        Text(
          '${fullDayLabel(review.week.start)} – '
          '${fullDayLabel(review.week.end)}',
          style: theme.textTheme.footnote?.copyWith(color: muted),
        ),
        const SizedBox(height: Insets.rowH),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${summary.percent}%',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: Insets.rowTrailingGap),
            Flexible(
              child: Text(
                'consistency',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.titleGap * 2),
        Text(
          'Of ${summary.eligible} '
          '${summary.eligible == 1 ? 'occurrence' : 'occurrences'} that were '
          'yours to make',
          style: theme.textTheme.footnote?.copyWith(color: muted),
        ),
        const SizedBox(height: Insets.rowH),
        Wrap(
          spacing: Insets.xl,
          runSpacing: Insets.rowTrailingGap,
          children: [
            _Count('Completed', summary.done),
            _Count('Partial', summary.partial),
            _Count('Missed', summary.missed),
            _Count('Skipped', summary.skipped, excluded: true),
          ],
        ),
        if (review.namesAreMeaningful) ...[
          const SizedBox(height: Insets.xl),
          _Named(
            overline: 'Went best',
            entry: review.best!,
            tinted: true,
          ),
          const SizedBox(height: Insets.rowH),
          // "Hardest", not "needs attention". The spec's own wording instructs
          // the user; the product principle two sections later says the app
          // describes behaviour and does not judge. A week can be hard without
          // anyone having failed at it, and the row that names it should not
          // arrive as a task.
          _Named(
            overline: 'Hardest',
            entry: review.hardest!,
            tinted: false,
          ),
        ],
        if (review.averageRecoveryDays != null) ...[
          const SizedBox(height: Insets.xl),
          _Recovery(days: review.averageRecoveryDays!),
        ],
      ],
    );
  }
}

/// A week the app has nothing honest to say about.
class _NothingToReview extends StatelessWidget {
  const _NothingToReview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.xl + Insets.rowH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Nothing to review', style: theme.textTheme.titleMedium),
            const SizedBox(height: Insets.rowTrailingGap),
            Text(
              'Nothing was expected last week, so there is no result to '
              'report. A quiet week is not a bad one.',
              textAlign: TextAlign.center,
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

class _Count extends StatelessWidget {
  const _Count(this.label, this.value, {this.excluded = false});

  final String label;
  final int value;

  /// Outside the score rather than inside it. Same treatment as Insights, and
  /// for the same reason: a skip never entered the denominator, and a tally
  /// rendered like Missed invites the one reading the accounting model exists
  /// to prevent.
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
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
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

class _Named extends StatelessWidget {
  const _Named({
    required this.overline,
    required this.entry,
    required this.tinted,
  });

  final String overline;
  final CommitmentWeek entry;

  /// Sage for the week's strongest. The other is left in ordinary ink rather
  /// than clay — principle 2 reserves the app's strongest negative for a
  /// closed, missed day, and a commitment that merely went less well than
  /// another has not earned it.
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final glyph = glyphFor(entry.commitment.icon);
    final percent = entry.summary.percent;

    return Semantics(
      label: '$overline: ${entry.commitment.name}, $percent percent',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            overline.toUpperCase(),
            style: theme.textTheme.sectionOverline?.copyWith(color: muted),
          ),
          const SizedBox(height: Insets.titleGap * 2),
          Row(
            children: [
              if (glyph != null) ...[
                Icon(glyph, size: 20, color: muted),
                const SizedBox(width: Insets.rowTrailingGap),
              ],
              Expanded(
                child: Text(
                  entry.commitment.name,
                  style: theme.textTheme.rowTitle,
                ),
              ),
              const SizedBox(width: Insets.rowTrailingGap),
              Text(
                '$percent%',
                style: theme.textTheme.tabularMeta?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tinted ? context.statusColors.done : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The number the app actually wants the user to leave with.
///
/// Last on the screen on purpose. `CLAUDE.md`: long-run consistency and
/// **recovery time** are the headline metrics, not streaks — and of everything
/// here, recovery is the only figure that says something encouraging about a
/// week that went badly.
class _Recovery extends StatelessWidget {
  const _Recovery({required this.days});

  final double days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.all(Insets.rowH),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.row),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.replay_rounded, size: 18, color: context.statusColors.done),
          const SizedBox(width: Insets.rowTrailingGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You come back within ${days.toStringAsFixed(1)} days',
                  style: theme.textTheme.rowTitle,
                ),
                const SizedBox(height: Insets.titleGap),
                Text(
                  'Recovering quickly matters more than never slipping.',
                  style: theme.textTheme.footnote?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
