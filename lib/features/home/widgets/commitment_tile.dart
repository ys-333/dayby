import 'package:flutter/material.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';

import '../today_view.dart';
import 'status_indicator.dart';

/// A single row: tap to advance it, long-press for everything else.
///
/// The tap target is the whole row rather than the indicator, because the core
/// promise is a sub-ten-second daily pass and hunting for a small circle is
/// what breaks that.
class CommitmentTile extends StatelessWidget {
  const CommitmentTile({
    required this.item,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final TodayItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = item.status == OccurrenceStatus.done;
    final muted = item.status == OccurrenceStatus.skipped ||
        item.status == OccurrenceStatus.paused;

    final subtitle = item.isPeriod
        ? '${item.completed} / ${item.target} ${item.periodLabel ?? ''}'.trim()
        : item.target > 1
            ? '${item.completed} / ${item.target}'
            : _statusWord(item.status);

    return Semantics(
      button: true,
      label: '${item.commitment.name}, $subtitle',
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              if (item.commitment.icon != null) ...[
                Text(
                  item.commitment.icon!,
                  style: const TextStyle(fontSize: 22),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.commitment.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        decoration: muted ? TextDecoration.lineThrough : null,
                        color: muted ? theme.colorScheme.outline : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // A countable row that is not yet finished shows "+", because
              // its tap adds one rather than completing outright. The
              // affordance has to match what the tap actually does.
              if (item.isCountable && !done && !muted)
                Semantics(
                  label: 'Add one',
                  child: Icon(
                    Icons.add_rounded,
                    color: theme.colorScheme.primary,
                  ),
                )
              else
                StatusIndicator(status: item.status),
            ],
          ),
        ),
      ),
    );
  }

  String _statusWord(OccurrenceStatus status) => switch (status) {
        OccurrenceStatus.done => 'Done',
        OccurrenceStatus.partial => 'Partial',
        OccurrenceStatus.missed => 'Missed',
        OccurrenceStatus.skipped => 'Skipped',
        OccurrenceStatus.paused => 'Paused',
        OccurrenceStatus.notScheduled => 'Not scheduled',
        OccurrenceStatus.pending => 'Not done yet',
      };
}
