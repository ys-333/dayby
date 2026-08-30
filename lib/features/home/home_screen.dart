import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riyaz/app/formatting.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/app/theme/tokens.dart';
import 'package:riyaz/app/theme/type_roles.dart';
import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/time/civil_date.dart';

import 'today_controller.dart';
import 'today_view.dart';
import 'widgets/commitment_tile.dart';
import 'widgets/period_tile.dart';
import 'widgets/recent_strip.dart';
import 'widgets/section_header.dart';
import 'package:riyaz/features/review/widgets/review_card.dart';

/// The tracking screen.
///
/// Three things the device pass found are answered here, and they are the
/// reason the layout is what it is:
///
/// * The greeting cost ~180px above the first row, so on a phone the list
///   began below the fold. It is gone. What replaced it — headline and strip —
///   is content about the day, and it scrolls away with the list.
/// * The FAB covered the last row permanently. Add moved into the day bar,
///   where it costs no vertical space and covers nothing.
/// * Daily rows and period targets rendered at identical weight, so a
///   "3× a week" target looked overdue every day of the week. They are now two
///   groups with two different row shapes.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDateProvider);
    final today = ref.watch(todayProvider);
    final view = ref.watch(todayViewProvider(date));

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DayBar(date: date, isToday: date == today),
            Expanded(
              child: view.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorState(message: '$e'),
                data: (data) => data.isEmpty
                    ? const _EmptyState()
                    : _TodayList(view: data, isToday: date == today),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Which day is on screen, how to move between days, and how to add.
///
/// Add lives here rather than in a floating button. A FAB is a 56dp disc
/// pinned over the bottom-right of the list, and on the one screen whose whole
/// job is a scrollable column of tap targets it permanently hides one of them.
/// In the bar it is always reachable, never overlapping, and costs no height
/// the day bar was not already spending.
class _DayBar extends ConsumerWidget {
  const _DayBar({required this.date, required this.isToday});

  final CivilDate date;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.contentInset, 4, Insets.contentInset, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () =>
                ref.read(selectedDateProvider.notifier).previousDay(),
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Previous day',
          ),
          Expanded(
            child: Text(
              isToday ? 'Today' : fullDayLabel(date),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            // Disabled on today: the future cannot be recorded.
            onPressed: isToday
                ? null
                : () => ref.read(selectedDateProvider.notifier).nextDay(),
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Next day',
          ),
          IconButton(
            onPressed: () => context.go('/add'),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add commitment',
          ),
        ],
      ),
    );
  }
}

class _TodayList extends ConsumerStatefulWidget {
  const _TodayList({required this.view, required this.isToday});

  final TodayView view;
  final bool isToday;

  @override
  ConsumerState<_TodayList> createState() => _TodayListState();
}

class _TodayListState extends ConsumerState<_TodayList> {
  static const Duration _undoWindow = Duration(seconds: 4);

  /// The undo bar's own timeout, owned here rather than left to the framework.
  ///
  /// Flutter arms a SnackBar's dismiss timer only from inside
  /// `ScaffoldMessengerState.build`, and on this screen that never happens when
  /// the bar is shown from the continuation after an awaited write: it animates
  /// in, settles with no frames pending, and then sits over the bottom of every
  /// tab forever. Reproduced on device and pinned in `snackbar_test.dart`.
  Timer? _undoTimer;

  TodayView get view => widget.view;

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final daily = view.daily;
    final period = view.period;

    return ListView(
      padding: const EdgeInsets.only(bottom: Insets.xl),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.rowH + Insets.contentInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Above the headline, and only on the days it has something to
              // say. A closed week is the one thing on this screen that is
              // more important than today.
              if (widget.isToday) const ReviewCard(),
              _Headline(view: view, isToday: widget.isToday),
              const SizedBox(height: Insets.rowH),
              _Strip(date: view.date, isToday: widget.isToday),
            ],
          ),
        ),
        if (daily.isNotEmpty) ...[
          _Group(
            title: 'Today',
            trailing: '${view.dailyDone} of ${view.dailyExpected}',
          ),
          for (final item in daily)
            CommitmentTile(
              item: item,
              onTap: () => _advance(context, item),
              onLongPress: () => _showActions(context, item),
            ),
        ],
        if (period.isNotEmpty) ...[
          _Group(
            title: _periodGroupTitle(period),
            // Principle 3, said out loud. Without it the split between the two
            // groups looks arbitrary; with it, the reason is on screen.
            trailing: 'Never late',
          ),
          for (final item in period)
            PeriodTile(
              item: item,
              onTap: () => _advance(context, item),
              onLongPress: () => _showActions(context, item),
            ),
        ],
        _MetPeriodsNote(view: view),
      ],
    );
  }

  /// "This week" when every target is weekly, "This month" when every target
  /// is monthly, and the neutral word when they are mixed — a heading that
  /// says "week" above a monthly row is worse than one that says neither.
  String _periodGroupTitle(List<TodayItem> period) {
    final nouns = {for (final item in period) item.periodNoun};
    if (nouns.length != 1) return 'Targets';
    return switch (nouns.single) {
      'week' => 'This week',
      'month' => 'This month',
      _ => 'Targets',
    };
  }

  /// A tap does the most likely thing and nothing else: finish a simple row,
  /// add one to a countable row, and un-tick a row already finished so an
  /// accidental tap is reversible without opening a menu.
  Future<void> _advance(
    BuildContext context,
    TodayItem item,
  ) async {
    final actions = ref.read(trackingActionsProvider);
    final token = switch (item.status) {
      OccurrenceStatus.done => await actions.clear(item, view.date),
      OccurrenceStatus.skipped => await actions.clear(item, view.date),
      _ when item.isCountable => await actions.increment(item, view.date),
      _ => await actions.markDone(item, view.date),
    };
    if (context.mounted) _offerUndo(context, token);
  }

  Future<void> _showActions(
    BuildContext context,
    TodayItem item,
  ) async {
    final actions = ref.read(trackingActionsProvider);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        // Scrollable: the sheet grows with the number of actions, and on a
        // short screen or with large text it must give rather than overflow.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  item.commitment.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(fullDayLabel(view.date)),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.contrast_rounded),
                title: const Text('Mark partial'),
                onTap: () => Navigator.pop(context, 'partial'),
              ),
              // Daily rows only. A skip settles one day, and a period is scored
              // over its target rather than its days, so skipping a day inside
              // "3x/week" has nothing to settle — the week is still asking for
              // three. Offering it here would record an event and visibly
              // change nothing.
              if (!item.isPeriod)
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline_rounded),
                  title: const Text('Skip'),
                  subtitle: const Text("Won't count against consistency"),
                  onTap: () => Navigator.pop(context, 'skip'),
                ),
              // Only offered once something is recorded: a note attaches to a
              // tracking event, so there is nothing to attach it to on an empty
              // day. Showing a dead menu item would be worse than hiding it.
              if (item.status != OccurrenceStatus.pending &&
                  item.status != OccurrenceStatus.missed)
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: const Text('Add note'),
                  onTap: () => Navigator.pop(context, 'note'),
                ),
              ListTile(
                leading: const Icon(Icons.backspace_outlined),
                title: const Text('Clear'),
                onTap: () => Navigator.pop(context, 'clear'),
              ),
              const Divider(height: 1),
              // The only way into the per-commitment screen. Its stats are the
              // point of tracking, so it cannot stay unreachable.
              ListTile(
                leading: const Icon(Icons.bar_chart_rounded),
                title: const Text('View details'),
                subtitle: const Text('Streaks, consistency and history'),
                onTap: () => Navigator.pop(context, 'details'),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !context.mounted) return;

    if (choice == 'note') {
      await _editNote(context, item);
      return;
    }

    if (choice == 'details') {
      context.push('/commitment/${item.commitment.id}');
      return;
    }

    final token = switch (choice) {
      'partial' => await actions.markPartial(item, view.date),
      'skip' => await actions.skip(item, view.date),
      _ => await actions.clear(item, view.date),
    };
    if (context.mounted) _offerUndo(context, token);
  }

  Future<void> _editNote(
    BuildContext context,
    TodayItem item,
  ) async {
    final note = await showDialog<String>(
      context: context,
      builder: (context) => _NoteDialog(
        title: item.commitment.name,
        initial: item.note,
      ),
    );
    if (note == null) return;

    await ref
        .read(trackingRepositoryProvider)
        .setNote(
          commitmentId: item.commitment.id,
          date: view.date,
          note: note.isEmpty ? null : note,
        );
  }

  void _offerUndo(BuildContext context, UndoToken token) {
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(token.label),
        duration: _undoWindow,
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => ref.read(trackingActionsProvider).undo(token),
        ),
      ),
    );

    final timer = Timer(_undoWindow, () {
      if (mounted) controller.close();
    });
    _undoTimer?.cancel();
    _undoTimer = timer;
    // Dismissed by the user, or replaced by the next action: stop our timeout
    // so it cannot close a later bar.
    controller.closed.then((_) => timer.cancel());
  }
}

/// The day's one big line.
class _Headline extends StatelessWidget {
  const _Headline({required this.view, required this.isToday});

  final TodayView view;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final text = dayHeadline(
      left: view.dailyLeft,
      done: view.dailyDone,
      expected: view.dailyExpected,
      isToday: isToday,
    );

    return Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.dayHeadline),
    );
  }
}

/// The strip, with its own loading and error behaviour.
///
/// It reads a wider range than the list does, so it resolves separately and
/// must never hold the list up. While it is loading it reserves its height and
/// draws nothing: a spinner here would put a spinner above the rows the user
/// opened the app to tap.
class _Strip extends ConsumerWidget {
  const _Strip({required this.date, required this.isToday});

  final CivilDate date;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(recentDaysProvider(date));
    final view = ref.watch(todayViewProvider(date)).value;

    final caption = !isToday
        ? 'Day closed'
        : view != null && view.dailyLeft == 0 && view.dailyExpected > 0
            ? 'Today counted'
            : 'Today still open';

    return days.maybeWhen(
      data: (days) => RecentStrip(days: days, caption: caption),
      orElse: () => const SizedBox(
        height: Sizes.stripCell + Insets.rowH,
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.rowH + Insets.contentInset,
          Insets.sectionGap,
          Insets.rowH + Insets.contentInset,
          Insets.sectionHeaderGap,
        ),
        child: SectionHeader(title: title, trailing: trailing),
      );
}

/// "Books and Long walk are done for the week."
///
/// The counterweight to a screen that otherwise only ever shows what is
/// outstanding. A met target drops out of the day's arithmetic entirely, and
/// without this line the work that earned it becomes invisible the moment it
/// is finished.
class _MetPeriodsNote extends StatelessWidget {
  const _MetPeriodsNote({required this.view});

  final TodayView view;

  @override
  Widget build(BuildContext context) {
    final byNoun = view.metPeriodsByNoun;
    if (byNoun.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final lines = [
      for (final entry in byNoun.entries)
        '${joinNames([for (final i in entry.value) i.commitment.name])} '
            '${entry.value.length == 1 ? 'is' : 'are'} done for the '
            '${entry.key}',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.rowH + Insets.contentInset,
        Insets.rowH,
        Insets.rowH + Insets.contentInset,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(Insets.rowTrailingGap),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(Radii.row),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.check_rounded,
              size: 18,
              color: context.statusColors.done,
            ),
            const SizedBox(width: Insets.rowTrailingGap),
            Expanded(
              child: Text(
                lines.join('\n'),
                style: theme.textTheme.footnote?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Owns its own controller so it is disposed with the dialog, not before it.
/// Disposing on the caller's side races the dialog's exit animation, which
/// still rebuilds the field on the way out.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.title, this.initial});

  final String title;
  final String? initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'What happened?',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Nothing to track yet.', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Start small.\nStay consistent.',
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        "Couldn't load today.\n$message",
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ),
  );
}
