import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riyaz/app/formatting.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/time/civil_date.dart';

import 'today_controller.dart';
import 'today_view.dart';
import 'widgets/commitment_tile.dart';

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
            _Header(date: date, isToday: date == today),
            Expanded(
              child: view.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorState(message: '$e'),
                data: (data) =>
                    data.isEmpty ? const _EmptyState() : _TodayList(view: data),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/add'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.date, required this.isToday});

  final CivilDate date;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final view = ref.watch(todayViewProvider(date)).value;
    final hour = ref.watch(clockProvider).nowUtc().toLocal().hour;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isToday)
            Text(
              '${greetingFor(hour)} 👋',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton(
                onPressed: () =>
                    ref.read(selectedDateProvider.notifier).previousDay(),
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Previous day',
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      isToday ? 'Today' : fullDayLabel(date),
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    if (isToday)
                      Text(
                        fullDayLabel(date),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
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
            ],
          ),
          if (view != null && view.total > 0) ...[
            const SizedBox(height: 12),
            _Progress(view: view),
          ],
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.view});

  final TodayView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = view.percent ?? 0;

    return Semantics(
      label: '$percent percent done, ${view.completed} of ${view.total}',
      child: Row(
        children: [
          Text(
            '$percent%',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: view.progress ?? 0,
                minHeight: 8,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${view.completed} / ${view.total}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayList extends ConsumerStatefulWidget {
  const _TodayList({required this.view});

  final TodayView view;

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
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: view.items.length,
      itemBuilder: (context, index) {
        final item = view.items[index];
        return CommitmentTile(
          item: item,
          onTap: () => _advance(context, item),
          onLongPress: () => _showActions(context, item),
        );
      },
    );
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
