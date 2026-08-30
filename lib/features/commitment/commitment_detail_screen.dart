import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riyaz/app/formatting.dart';
import 'package:riyaz/app/glyphs.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/app/theme/tokens.dart';
import 'package:riyaz/app/theme/type_roles.dart';
import 'package:riyaz/domain/analytics/consistency_summary.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/app/providers.dart';

import 'commitment_detail_controller.dart';
import 'widgets/edit_sheet.dart';
import 'widgets/twelve_week_grid.dart';
import 'widgets/trend_chart.dart';

class CommitmentDetailScreen extends ConsumerStatefulWidget {
  const CommitmentDetailScreen({required this.commitmentId, super.key});

  final String commitmentId;

  @override
  ConsumerState<CommitmentDetailScreen> createState() =>
      _CommitmentDetailScreenState();
}

class _CommitmentDetailScreenState
    extends ConsumerState<CommitmentDetailScreen> {
  static const Duration _undoWindow = Duration(seconds: 5);

  /// The undo bar's own timeout, owned here rather than left to the framework.
  ///
  /// Flutter arms a SnackBar's dismiss timer only from inside
  /// `ScaffoldMessengerState.build`, which never happens when the bar is shown
  /// from the continuation after an awaited write: it animates in, settles
  /// with no frames pending, and then sits there indefinitely. Found on device
  /// on the Today screen and pinned in `snackbar_test.dart`; this screen writes
  /// the same way, so it needs the same handling.
  Timer? _undoTimer;

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(commitmentDetailProvider(widget.commitmentId));
    final commitment = detail.value?.commitment;
    final archived = commitment?.state == CommitmentState.archived;
    final pause = ref.watch(openPauseProvider(widget.commitmentId)).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(commitment?.name ?? ''),
        actions: [
          if (commitment != null)
            PopupMenuButton<_Action>(
              onSelected: (action) => _run(action, commitment),
              itemBuilder: (context) => [
                const PopupMenuItem(value: _Action.edit, child: Text('Edit')),
                // Not offered on an archived commitment: its schedule is
                // already closed, so there is nothing left to suspend and
                // "Paused" on top of "Archived" would be two words for one
                // state.
                if (!archived)
                  PopupMenuItem(
                    value: pause == null ? _Action.pause : _Action.resume,
                    child: Text(pause == null ? 'Pause' : 'Resume'),
                  ),
                PopupMenuItem(
                  value: archived ? _Action.unarchive : _Action.archive,
                  child: Text(archived ? 'Unarchive' : 'Archive'),
                ),
              ],
            ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) => data == null
            ? const Center(child: Text('This commitment no longer exists.'))
            : _Body(detail: data),
      ),
    );
  }

  Future<void> _run(_Action action, Commitment commitment) async {
    final actions = ref.read(commitmentActionsProvider);
    switch (action) {
      case _Action.edit:
        final frequency = await actions.currentFrequency(commitment.id);
        if (frequency == null || !mounted) return;
        final edit = await showModalBottomSheet<CommitmentEdit>(
          context: context,
          isScrollControlled: true,
          builder: (context) =>
              EditSheet(commitment: commitment, frequency: frequency),
        );
        if (edit == null || edit.isEmpty || !mounted) return;
        await actions.edit(
          commitmentId: commitment.id,
          name: edit.name,
          icon: edit.icon,
          clearIcon: edit.clearIcon,
          frequency: edit.frequency,
        );
        if (mounted) {
          _say(
            edit.frequency == null
                ? 'Saved.'
                : 'Saved. Your history is unchanged.',
          );
        }
      case _Action.archive:
        await actions.archive(commitment.id);
        if (mounted) {
          _say(
            'Archived. Its history is kept.',
            undo: () => actions.unarchive(commitment.id),
          );
        }
      case _Action.unarchive:
        await actions.unarchive(commitment.id);
        if (mounted) {
          _say(
            'Back in your daily list.',
            undo: () => actions.archive(commitment.id),
          );
        }
      case _Action.pause:
        final from = ref.read(todayProvider);
        await actions.pause(commitment.id);
        if (mounted) {
          _say(
            'Paused. These days will not count as missed.',
            undo: () => actions.cancelPause(commitment.id, from),
          );
        }
      case _Action.resume:
        final from = await actions.resume(commitment.id);
        if (mounted) {
          _say(
            'Resumed from today.',
            undo: from == null
                ? null
                : () => actions.restorePause(commitment.id, from),
          );
        }
    }
  }

  void _say(String message, {Future<void> Function()? undo}) {
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: _undoWindow,
        action: undo == null
            ? null
            : SnackBarAction(label: 'UNDO', onPressed: undo),
      ),
    );
    final timer = Timer(_undoWindow, () {
      if (mounted) controller.close();
    });
    _undoTimer?.cancel();
    _undoTimer = timer;
    controller.closed.then((_) => timer.cancel());
  }
}

enum _Action { edit, pause, resume, archive, unarchive }

/// Says the commitment is paused, from when, and what that means for scoring.
///
/// The reassurance is the point. A user pauses because they are injured or
/// away, and the fear a tracker creates in that moment is that the streak is
/// dying while they are not looking. Saying "these days are not counted as
/// missed" on the screen showing their numbers is worth more than any
/// indicator on the row.
///
/// Renders nothing when the commitment is not paused, rather than being
/// conditionally built by the caller — the pause state lives in its own
/// stream, and having the widget own the decision keeps that stream out of the
/// body's build.
class _PausedBanner extends ConsumerWidget {
  const _PausedBanner({required this.commitmentId});

  final String commitmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pause = ref.watch(openPauseProvider(commitmentId)).value;
    if (pause == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: Insets.rowH),
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.rowH,
        vertical: Insets.rowV,
      ),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(Radii.row),
      ),
      child: Row(
        children: [
          Icon(
            Icons.pause_circle_outline_rounded,
            size: 18,
            color: context.statusColors.paused,
          ),
          const SizedBox(width: Insets.rowTrailingGap),
          Expanded(
            child: Text(
              'Paused since ${fullDayLabel(pause.from)}. '
              'These days are not counted as missed.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Says the commitment is out of the daily list, and that nothing was lost.
///
/// Stated rather than implied: "archived" is the kind of word people read as
/// "deleted", and this screen is still showing a year of the history that
/// archiving deliberately keeps.
class _ArchivedBanner extends StatelessWidget {
  const _ArchivedBanner({required this.archivedOn});

  final String? archivedOn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: Insets.rowH),
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.rowH,
        vertical: Insets.rowV,
      ),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(Radii.row),
      ),
      child: Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: Insets.rowTrailingGap),
          Expanded(
            child: Text(
              archivedOn == null
                  ? 'Archived. Its history is kept and still counts below.'
                  : 'Archived $archivedOn. Its history is kept and still '
                        'counts below.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.detail});

  final CommitmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final streaks = detail.streaks;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Insets.rowH,
        Insets.titleGap * 4,
        Insets.rowH,
        Insets.xl + Insets.rowH,
      ),
      children: [
        if (detail.commitment.state == CommitmentState.archived)
          _ArchivedBanner(archivedOn: detail.commitment.archivedOn?.iso)
        else
          _PausedBanner(commitmentId: detail.commitment.id),
        _Heading(detail: detail),
        const SizedBox(height: Insets.sectionGap),
        _LeadFigure(detail: detail),
        const SizedBox(height: Insets.xl),
        const _SectionTitle('Last twelve weeks'),
        TwelveWeekGrid(detail: detail),
        const SizedBox(height: Insets.xl),
        const _SectionTitle('Momentum'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Stat(
              label: 'A typical run',
              value: streaks.averageStreak == 0
                  ? '—'
                  : streaks.averageStreak.toStringAsFixed(
                      streaks.averageStreak % 1 == 0 ? 0 : 1,
                    ),
              unit: streaks.averageStreak == 0 ? '' : 'days',
            ),
            _Stat(
              label: 'Your best run',
              value: '${streaks.longest}',
              unit: streaks.longest == 1 ? 'day' : 'days',
            ),
            _Stat(
              label: 'To come back',
              // Null until a lapse has actually been recovered from. Showing
              // "0 days" would claim a resilience that has not been shown.
              value: streaks.averageRecoveryDays == null
                  ? '—'
                  : streaks.averageRecoveryDays!.toStringAsFixed(1),
              unit: streaks.averageRecoveryDays == null ? '' : 'days',
            ),
          ],
        ),
        const SizedBox(height: Insets.xl),
        // The secondary windows, deliberately small. The board's argument
        // holds: fifteen equal-weight figures is a wall nobody reads, and the
        // one that matters is already the largest thing on the screen.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SmallStat.percent('This week', detail.thisWeek),
            _SmallStat.percent('90 days', detail.last90),
            _SmallStat.percent('This year', detail.thisYear),
            _SmallStat(
              label: 'Skipped',
              value: '${detail.thisYear.skipped}',
              // Surfaced separately rather than hidden, and never scored: a
              // skip is a decision the user made, and the count of them is
              // information about the year, not a deduction from it.
              dim: true,
            ),
          ],
        ),
        const SizedBox(height: Insets.xl),
        const _SectionTitle('Rolling 7-day consistency'),
        TrendChart(points: detail.trend),
        if (detail.latestNote != null) ...[
          const SizedBox(height: Insets.xl),
          const _SectionTitle('Latest note'),
          _Note(note: detail.latestNote!),
        ],
      ],
    );
  }
}

/// The commitment's mark, name and how long it has been running.
class _Heading extends StatelessWidget {
  const _Heading({required this.detail});

  final CommitmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glyph = glyphFor(detail.commitment.icon);

    // Derived from the occurrences the screen already resolved rather than
    // read from the schedule. `ResolvedHistory` carries no schedules, and
    // widening a type shared with history, analytics and insights for one
    // subtitle would make three screens pay for a label only this one shows.
    // So the line states what can be said truthfully from what is here: the
    // period for a period target, and the start date always.
    final since =
        'since ${fullDayLabel(detail.commitment.startedOn)} '
        '${detail.commitment.startedOn.year}';
    final subtitle = detail.periodLabel == null
        ? since.replaceRange(0, 1, 'S')
        : 'A target every ${detail.periodLabel} · $since';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (glyph != null) ...[
          Icon(glyph, size: 26, color: context.statusColors.done),
          const SizedBox(width: Insets.rowTrailingGap),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.commitment.name,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: Insets.titleGap),
              Text(
                subtitle,
                style: theme.textTheme.footnote?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One number, large, with the sentence that makes it mean something.
///
/// The screen used to open with fifteen figures at the same weight, which is a
/// wall rather than an answer. This is the one the user came for, and the line
/// under it says what the denominator actually was — a percentage with no
/// stated base is a number you cannot argue with or learn from.
class _LeadFigure extends StatelessWidget {
  const _LeadFigure({required this.detail});

  final CommitmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = detail.thisMonth;
    final muted = theme.colorScheme.onSurfaceVariant;
    final days = summary.eligible;

    return Semantics(
      container: true,
      label: summary.percent == null
          ? 'No consistency this month yet'
          : '${summary.percent} percent this month, over $days '
                '${detail.isPeriod ? 'closed targets' : 'scheduled days'}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                summary.percent == null ? '—' : '${summary.percent}%',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: Insets.rowTrailingGap),
              Flexible(
                child: Text(
                  'this month',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.titleGap * 2),
          Text(
            // An em dash rather than 0%: a month with nothing settled yet has
            // no consistency, and rendering that as zero is a verdict on a
            // month the user has not finished.
            days == 0
                ? 'Nothing has settled this month yet'
                : detail.isPeriod
                ? 'Of $days closed ${days == 1 ? 'target' : 'targets'} '
                      'this month'
                : 'Of $days scheduled '
                      '${days == 1 ? 'day' : 'days'} this month',
            style: theme.textTheme.footnote?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

/// The most recent thing the user wrote, quoted.
///
/// Their own words about their own week are worth more than another figure,
/// and until now the only way to see one was to long-press the row it belonged
/// to and open a dialog.
class _Note extends StatelessWidget {
  const _Note({required this.note});

  final DatedNote note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // `IntrinsicHeight` so the rule beside the quote is exactly as tall as the
    // quote. A stretched Row inside a ListView asks for infinite height, and a
    // fixed bar height would be wrong for every note but one.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 2,
            decoration: BoxDecoration(
              color: context.statusColors.done,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: Insets.rowTrailingGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(note.text, style: theme.textTheme.bodyMedium),
                const SizedBox(height: Insets.titleGap),
                Text(
                  fullDayLabel(note.date),
                  style: theme.textTheme.footnote?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A secondary figure: small, quiet, and never competing with the lead.
class _SmallStat extends StatelessWidget {
  const _SmallStat({
    required this.label,
    required this.value,
    this.dim = false,
  });

  factory _SmallStat.percent(String label, ConsistencySummary summary) =>
      _SmallStat(
        label: label,
        value: summary.percent == null ? '—' : '${summary.percent}%',
      );

  final String label;
  final String value;

  /// True for a count that is information rather than performance.
  final bool dim;

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
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: dim ? muted : null,
            ),
          ),
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
