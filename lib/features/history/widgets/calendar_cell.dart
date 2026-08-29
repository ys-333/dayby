import 'package:flutter/material.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/app/theme/tokens.dart';
import 'package:riyaz/domain/analytics/day_band.dart';

import '../history_controller.dart';

/// A single calendar day.
///
/// The band is carried by **fill and shape**, not hue: strong is solid, partial
/// is a filled container with a ring, weak is a bare ring, and future is the
/// faintest outline with no fill. Colour reinforces; it never carries meaning
/// on its own. Which colour that is comes from `BandColors`.
class CalendarCell extends StatelessWidget {
  const CalendarCell({
    required this.day,
    required this.isToday,
    required this.onTap,
    super.key,
  });

  final CalendarDay day;
  final bool isToday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final band = context.bandColors.forBand(day.band);

    final label = switch (day.band) {
      DayBand.future => 'not yet',
      DayBand.none => 'nothing tracked',
      _ => '${day.summary.percent} percent',
    };

    return Semantics(
      label: '${day.date.iso}, $label',
      button: onTap != null,
      child: Opacity(
        opacity: day.inMonth ? 1 : 0.35,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Center(
            child: Container(
              width: Sizes.calendarCell,
              height: Sizes.calendarCell,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: band.fill,
                border: Border.all(
                  color: isToday ? context.bandColors.todayRing : band.border,
                  width: isToday ? 2.5 : 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '${day.date.day}',
                style: TextStyle(
                  fontSize: 13,
                  color: band.ink,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
