import 'package:flutter/material.dart';
import 'package:riyaz/app/theme/band_colors.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/app/theme/tokens.dart';
import 'package:riyaz/app/theme/type_roles.dart';
import 'package:riyaz/domain/analytics/day_band.dart';

import '../today_controller.dart';

/// The last two weeks as fourteen banded cells.
///
/// This is what replaced the progress bar. The bar scored a day still being
/// lived; the strip scores only days that are over and draws the current one
/// as an outline, so the screen can show "how it has been going" without
/// grading a morning.
///
/// It is decoration in the strict sense — nothing here is tappable, and every
/// cell is also reachable, dated and labelled on the history screen. So the
/// whole thing carries one summary label and its fourteen children are hidden
/// from the screen reader rather than read out as fourteen anonymous boxes.
class RecentStrip extends StatelessWidget {
  const RecentStrip({required this.days, required this.caption, super.key});

  final List<StripDay> days;

  /// The right-hand note: whether the anchor day is settled yet.
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bands = context.bandColors;
    final muted = theme.colorScheme.onSurfaceVariant;

    return Semantics(
      label: _semanticLabel,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              height: Sizes.stripCell,
              child: Row(
                children: [
                  for (final (index, day) in days.indexed) ...[
                    if (index > 0) const SizedBox(width: Sizes.stripGap),
                    Expanded(child: _Cell(day: day, bands: bands)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: Insets.titleGap * 3),
          // Both halves are flexible and both wrap. Two unconstrained Texts
          // with `spaceBetween` fit at 13sp and overflow the moment the user
          // raises their text size — which is the one setting that must never
          // break a screen.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  'Last ${days.length} days',
                  style: theme.textTheme.footnote?.copyWith(color: muted),
                ),
              ),
              const SizedBox(width: Insets.rowTrailingGap),
              Flexible(
                child: Text(
                  caption,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.footnote?.copyWith(color: muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String get _semanticLabel {
    final settled = days.where((d) => !d.isAnchor).toList();
    final strong = settled.where((d) => d.band == DayBand.strong).length;
    return 'Last ${days.length} days: '
        '$strong of ${settled.length} settled days were strong. $caption.';
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.day, required this.bands});

  final StripDay day;
  final BandColors bands;

  @override
  Widget build(BuildContext context) {
    final style = bands.forBand(day.band);
    // The anchor keeps its own band's fill and takes the today ring on top of
    // it. Recolouring the cell would say the day being viewed is a *status*,
    // which is the mistake `BandColors.todayRing` exists to avoid.
    final border = day.isAnchor
        ? Border.all(color: bands.todayRing, width: 1.5)
        : style.fill == Colors.transparent
            ? Border.all(color: style.border, width: style.width)
            : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.fill,
        border: border,
        borderRadius: BorderRadius.circular(Sizes.stripRadius),
      ),
    );
  }
}
