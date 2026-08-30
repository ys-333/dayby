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
              // `stretch`, and it is load-bearing. A cell is a childless
              // `DecoratedBox`, so under the default `center` alignment it
              // sizes to the child it does not have and collapses to zero
              // height — the SizedBox reserves 24dp and the cells paint one
              // pixel inside it. Found on a device: the whole strip rendered
              // as a single faint dash, because only today's brighter ring was
              // visible at all. Nothing threw, and no test that merely renders
              // the widget can notice.
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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

/// One day, as a step on the heat ramp.
///
/// **Not `BandColors`.** The strip reached for the calendar's vocabulary at
/// first and it was the wrong one, visibly so on a device: a weak day there is
/// carried by a 2.5px clay ring, which is 7.4% of a 34dp calendar cell but
/// 10.4% of this 24dp one, with no numeral inside to soften it. Fourteen of
/// them shoulder to shoulder under the day's headline read as a row of alarms
/// — the exact opposite of what a countdown that refuses to score you is for.
///
/// `Palette.heat` is the right vocabulary and says so itself: the calendar
/// samples only its two ends because a mid-tone fill cannot carry a numeral,
/// and *"the full ramp is for a grid with no text in it"*. This is that grid.
/// It is also what the design board drew — five fills, no rings, no clay
/// anywhere on this component.
///
/// **Why lightness alone is allowed here**, when nothing else in the app may
/// do that: a monotonic ramp *is* a non-colour encoding, and this strip is
/// decorative besides. It states no per-day verdict, nothing in it is
/// tappable, its summary is spoken in one semantic label, and every day it
/// shows is also dated, labelled and individually reachable on the history
/// screen. The calendar cannot lean on lightness because a reader has to
/// distinguish *this* day from *that* one; here they only have to see a shape.
class _Cell extends StatelessWidget {
  const _Cell({required this.day, required this.bands});

  final StripDay day;
  final BandColors bands;

  /// Where each band sits on the five-step ramp.
  ///
  /// Step 3 is deliberately skipped. [DayBand] has nothing between partial and
  /// strong, so leaving the gap there puts the ramp's largest jump at the one
  /// boundary worth noticing — a day that actually went well — instead of
  /// spending it in the middle where it would say nothing.
  static int _step(DayBand band) => switch (band) {
        DayBand.none => 0,
        DayBand.weak => 1,
        DayBand.partial => 2,
        DayBand.strong => 4,
        DayBand.future => 0,
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    // Principle 5, and the one exception to "every cell is a fill": a day that
    // has not been lived is an outline. Nothing unlived is drawn as anything
    // else, least of all as an empty day.
    if (day.band == DayBand.future) {
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: palette.futureRing),
          borderRadius: BorderRadius.circular(Sizes.stripRadius),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.heat[_step(day.band)],
        // The anchor keeps its own step and takes the today ring on top of it.
        // Recolouring the cell would say the day being viewed is a *status*,
        // which is the mistake `BandColors.todayRing` exists to avoid.
        border: day.isAnchor
            ? Border.all(color: bands.todayRing, width: 1.5)
            : null,
        borderRadius: BorderRadius.circular(Sizes.stripRadius),
      ),
    );
  }
}
