import 'package:flutter/material.dart';
import 'package:riyaz/domain/analytics/day_band.dart';

import '../history_controller.dart';

/// A single calendar day.
///
/// The band is carried by **fill and shape**, not hue: strong is solid, partial
/// is a filled container with a ring, weak is a bare ring, and future is the
/// faintest outline with no fill. Colour reinforces; it never carries meaning
/// on its own.
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
    final scheme = Theme.of(context).colorScheme;

    final (bg, border, fg) = switch (day.band) {
      DayBand.strong => (scheme.primary, scheme.primary, scheme.onPrimary),
      DayBand.partial => (
          scheme.primaryContainer,
          scheme.primary,
          scheme.onPrimaryContainer,
        ),
      DayBand.weak =>
        (Colors.transparent, scheme.error, scheme.onSurface),
      DayBand.none => (
          Colors.transparent,
          scheme.outlineVariant,
          scheme.onSurfaceVariant,
        ),
      // Future: faintest outline, never a fill, never an error colour. A day
      // that has not happened cannot have been failed.
      DayBand.future => (
          Colors.transparent,
          scheme.outlineVariant.withValues(alpha: 0.4),
          scheme.outline,
        ),
    };

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
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bg,
                border: Border.all(
                  color: isToday ? scheme.tertiary : border,
                  width: isToday ? 2.5 : 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '${day.date.day}',
                style: TextStyle(
                  fontSize: 13,
                  color: fg,
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
