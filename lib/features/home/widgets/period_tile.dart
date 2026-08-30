import 'package:flutter/material.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/app/theme/tokens.dart';
import 'package:riyaz/app/theme/type_roles.dart';

import '../today_view.dart';
import 'commitment_icon.dart';

/// A week or month target: name, progress pips, and a tally.
///
/// Deliberately not a [CommitmentTile] with a different subtitle. A period row
/// has no status to show today — it cannot be done-for-today, and it cannot be
/// missed until its period closes — so it shows *how far through the target it
/// is* and nothing else. Giving it a tick or a cross would answer a question
/// the week has not asked yet.
class PeriodTile extends StatelessWidget {
  const PeriodTile({
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
    final met = item.isDone;
    final tally = '${item.completed} of ${item.target}';

    return Semantics(
      button: true,
      label: '${item.commitment.name}, $tally ${item.periodLabel ?? ''}'.trim(),
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
              CommitmentIcon(icon: item.commitment.icon, dimmed: met),
              Expanded(
                child: Text(
                  item.commitment.name,
                  style: theme.textTheme.rowTitle?.copyWith(
                    color: met ? status.muted : null,
                  ),
                ),
              ),
              const SizedBox(width: Insets.rowTrailingGap),
              // Pips and tally share one wrapping group so the tally drops
              // under the pips when the row is tight, rather than pushing the
              // whole Row past its width.
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: Insets.rowTrailingGap,
                  runSpacing: Insets.titleGap * 2,
                  children: [
                    if (item.target <= Sizes.maxPips)
                      _Pips(completed: item.completed, target: item.target),
                    Text(
                      tally,
                      style: theme.textTheme.tabularMeta?.copyWith(
                        color: met
                            ? status.done
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One dot per required completion, filled as they land.
///
/// Wraps rather than scrolls: at 1.8× text scale the row's text grows and the
/// pips must give way instead of forcing an overflow.
class _Pips extends StatelessWidget {
  const _Pips({required this.completed, required this.target});

  final int completed;
  final int target;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;

    return Wrap(
      spacing: Sizes.periodPipGap,
      runSpacing: Sizes.periodPipGap,
      children: [
        for (var i = 0; i < target; i++)
          Container(
            width: Sizes.periodPip,
            height: Sizes.periodPip,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < completed ? status.done : Colors.transparent,
              border: i < completed
                  ? null
                  : Border.all(color: status.pending, width: 1),
            ),
          ),
      ],
    );
  }
}
