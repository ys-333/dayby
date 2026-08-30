import 'package:flutter/material.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/app/theme/tokens.dart';
import 'package:riyaz/app/theme/type_roles.dart';

import '../today_view.dart';
import 'commitment_icon.dart';
import 'status_indicator.dart';

/// A daily row: tap to advance it, long-press for everything else.
///
/// The tap target is the whole row rather than the indicator, because the core
/// promise is a sub-ten-second daily pass and hunting for a small circle is
/// what breaks that.
///
/// Period targets do **not** come here — see [PeriodTile]. Splitting the two
/// is principle 3 of the design system: a 3×/week target cannot be behind on a
/// Tuesday, so it must not sit in a list of things that can.
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
    final status = context.statusColors;
    final recessive = item.isDone || item.isExcluded;

    // Skipped and paused rows are *not* struck through. A skip is a decision
    // the user made, not a deletion, and strikethrough is the typography of
    // something cancelled or wrong.
    final meta = _metaLine;

    return Semantics(
      button: true,
      label: _semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(Radii.row),
        child: Container(
          constraints: const BoxConstraints(minHeight: Sizes.rowMinHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.rowH,
            vertical: Insets.rowV,
          ),
          child: Row(
            children: [
              CommitmentIcon(icon: item.commitment.icon, dimmed: recessive),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.commitment.name,
                      style: theme.textTheme.rowTitle?.copyWith(
                        color: recessive ? status.muted : null,
                      ),
                    ),
                    if (meta != null) ...[
                      const SizedBox(height: Insets.titleGap),
                      Text(
                        meta,
                        style: theme.textTheme.rowMeta?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Insets.rowTrailingGap),
              // A countable row that is not yet finished shows "+", because
              // its tap adds one rather than completing outright. The
              // affordance has to match what the tap actually does.
              if (item.isCountable && !item.isDone && !item.isExcluded)
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

  /// The second line, or null when the row says everything on one.
  ///
  /// A pending row shows nothing here: an open ring already says "not yet",
  /// and a column of "Not done yet" under every untouched commitment was the
  /// noise the redesign removed. What survives is the states a mark cannot
  /// carry — a tally, a status the user chose, and their own note.
  String? get _metaLine {
    final parts = [
      if (item.target > 1) '${item.completed} / ${item.target}',
      if (item.statusCaption != null) item.statusCaption!,
      if (item.note != null && item.note!.isNotEmpty) item.note!,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String get _semanticLabel {
    final state = item.statusCaption ?? (item.isDone ? 'Done' : 'Not done yet');
    final meta = _metaLine;
    return meta == null
        ? '${item.commitment.name}, $state'
        : '${item.commitment.name}, $state, $meta';
  }
}
