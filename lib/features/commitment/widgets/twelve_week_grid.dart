import 'package:flutter/material.dart';
import 'package:riyaz/app/formatting.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/app/theme/tokens.dart';
import 'package:riyaz/app/theme/type_roles.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';

import '../commitment_detail_controller.dart';

/// Twelve weeks of one commitment, dated.
///
/// It replaces thirty undated circles. Those showed a *sequence* — this, then
/// this, then this — with nothing to hang it on, so a gap could not be placed
/// in a week or a month and therefore could not be learned from. A grid whose
/// rows are weekdays and whose columns are weeks answers the question the
/// strip was really being asked: **when do I drop this?**
///
/// Every mark is a shape before it is a colour, the same rule
/// `StatusIndicator` follows: a solid cell, a half-filled one, a bare ring, a
/// dot, a faint block. A reader who cannot separate sage from clay still reads
/// the grid.
class TwelveWeekGrid extends StatelessWidget {
  const TwelveWeekGrid({required this.detail, super.key});

  final CommitmentDetail detail;

  /// Room for the weekday initials down the left edge.
  static const double _gutter = 18;
  static const double _gap = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weeks = detail.grid.length ~/ 7;
    final muted = theme.colorScheme.onSurfaceVariant;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Square cells sized to whatever width is left, rather than a fixed
        // size that overflows a 320dp phone.
        final cell =
            ((constraints.maxWidth - _gutter - _gap * (weeks - 1)) / weeks)
                .floorToDouble()
                .clamp(6.0, 28.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MonthRuler(
              detail: detail,
              weeks: weeks,
              cell: cell,
              gap: _gap,
              gutter: _gutter,
              style: theme.textTheme.labelSmall?.copyWith(color: muted),
            ),
            const SizedBox(height: Insets.titleGap * 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _gutter,
                  child: Column(
                    children: [
                      for (var row = 0; row < 7; row++) ...[
                        if (row > 0) const SizedBox(height: _gap),
                        SizedBox(
                          height: cell,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            // Alternate days only. Seven initials at this size
                            // is more ink than the grid itself.
                            child: Text(
                              row.isEven
                                  ? weekdayName(
                                      detail.gridStart.plusDays(row),
                                    ).substring(0, 1)
                                  : '',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: muted, fontSize: 9),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                for (var week = 0; week < weeks; week++) ...[
                  if (week > 0) const SizedBox(width: _gap),
                  Column(
                    children: [
                      for (var row = 0; row < 7; row++) ...[
                        if (row > 0) const SizedBox(height: _gap),
                        _Cell(
                          day: detail.grid[week * 7 + row],
                          isPeriod: detail.isPeriod,
                          size: cell,
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: Insets.rowTrailingGap),
            _Legend(isPeriod: detail.isPeriod),
          ],
        );
      },
    );
  }
}

/// Month initials above the columns they start.
///
/// A label appears on the first week whose Monday falls in a new month, so the
/// twelve columns carry three or four marks rather than twelve — enough to
/// place a gap in the year, not enough to compete with the grid.
class _MonthRuler extends StatelessWidget {
  const _MonthRuler({
    required this.detail,
    required this.weeks,
    required this.cell,
    required this.gap,
    required this.gutter,
    required this.style,
  });

  final CommitmentDetail detail;
  final int weeks;
  final double cell;
  final double gap;
  final double gutter;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    var previous = -1;
    return Row(
      children: [
        SizedBox(width: gutter),
        for (var week = 0; week < weeks; week++) ...[
          if (week > 0) SizedBox(width: gap),
          SizedBox(
            width: cell,
            child: () {
              final start = detail.gridStart.plusDays(week * 7);
              final show = start.month != previous;
              previous = start.month;
              return show
                  ? Text(
                      shortMonth(start),
                      style: style,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                    )
                  : const SizedBox.shrink();
            }(),
          ),
        ],
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.day,
    required this.isPeriod,
    required this.size,
  });

  final GridDay day;
  final bool isPeriod;
  final double size;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;
    final palette = context.palette;
    final radius = BorderRadius.circular(size / 4);

    Widget box({Color? fill, Color? ring, double width = 1, Widget? child}) =>
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: ring == null ? null : Border.all(color: ring, width: width),
          ),
          child: child,
        );

    Widget dot(Color colour) => Center(
          child: Container(
            width: size / 3,
            height: size / 3,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
        );

    // A day the user has not lived is an outline and nothing else. This is
    // checked before the status so a pending occurrence in the current week
    // cannot borrow a failure's shape.
    if (day.isFuture) {
      return _Labelled(day: day, child: box(ring: palette.futureRing));
    }

    // A period commitment's grid says only where the work landed. Its days
    // were never individually owed, so none of them can be done or missed.
    if (isPeriod) {
      return _Labelled(
        day: day,
        child: day.creditedToPeriod
            ? box(fill: palette.line, child: dot(status.done))
            : box(fill: palette.line),
      );
    }

    return _Labelled(
      day: day,
      child: switch (day.status) {
        OccurrenceStatus.done => box(fill: status.done),
        // Half-filled, not tinted: partial is the one status whose meaning is
        // literally "some of it", and a shape can say that where a hue cannot.
        OccurrenceStatus.partial => ClipRRect(
            borderRadius: radius,
            child: box(
              ring: status.partial,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: 0.5,
                  widthFactor: 1,
                  child: ColoredBox(color: status.partial),
                ),
              ),
            ),
          ),
        OccurrenceStatus.missed => box(ring: status.missed),
        OccurrenceStatus.skipped => box(
            fill: palette.line,
            child: dot(status.skipped),
          ),
        OccurrenceStatus.pending => box(ring: palette.pendingRing),
        // Nothing was expected: an off day, a pause, or before the commitment
        // began. Faintest of all, and never a failure.
        _ => box(fill: palette.line),
      },
    );
  }
}

/// Gives one cell its date and state out loud.
///
/// Eighty-four cells is a lot of semantics, but the alternative is a screen
/// reader meeting a wall of unlabelled boxes — and the grid is the only place
/// this screen states what happened on a *particular* day.
class _Labelled extends StatelessWidget {
  const _Labelled({required this.day, required this.child});

  final GridDay day;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final state = day.isFuture
        ? 'not yet'
        : day.creditedToPeriod
            ? 'counted toward the target'
            : switch (day.status) {
                OccurrenceStatus.done => 'done',
                OccurrenceStatus.partial => 'partial',
                OccurrenceStatus.missed => 'missed',
                OccurrenceStatus.skipped => 'skipped',
                OccurrenceStatus.pending => 'not done yet',
                _ => 'nothing expected',
              };
    return Semantics(
      label: '${fullDayLabel(day.date)}: $state',
      child: Tooltip(
        message: '${fullDayLabel(day.date)} — $state',
        child: child,
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.isPeriod});

  final bool isPeriod;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final palette = context.palette;

    Widget key(Widget swatch, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 11, height: 11, child: swatch),
            const SizedBox(width: Insets.titleGap * 3),
            Text(
              label,
              style: theme.textTheme.footnote
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        );

    Widget swatch({Color? fill, Color? ring, Widget? child}) => DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(3),
            border: ring == null ? null : Border.all(color: ring),
          ),
          child: child,
        );

    Widget dot(Color colour) => Center(
          child: Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
        );

    return Wrap(
      spacing: Insets.rowGap,
      runSpacing: Insets.titleGap * 3,
      children: isPeriod
          ? [
              // Named apart from "Done" on purpose, exactly as the week grid
              // names it: a credited day is where the work fell, not a day
              // that was owed.
              key(
                swatch(fill: palette.line, child: dot(status.done)),
                'Counted toward a target',
              ),
              key(swatch(fill: palette.line), 'Not owed on any one day'),
              key(swatch(ring: palette.futureRing), 'Not yet'),
            ]
          : [
              key(swatch(fill: status.done), 'Done'),
              key(swatch(ring: status.partial), 'Partial'),
              key(swatch(ring: status.missed), 'Missed'),
              key(
                swatch(fill: palette.line, child: dot(status.skipped)),
                'Skipped',
              ),
              key(swatch(ring: palette.futureRing), 'Not yet'),
            ],
    );
  }
}
