import 'package:flutter/material.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/app/theme/tokens.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';

/// Renders a status with a distinct **shape and glyph**, never colour alone.
///
/// Colour is an accent here, not the signal. Roughly one in twelve men has some
/// colour-vision deficiency, and a tracker whose entire meaning is red-vs-green
/// is unreadable to them — so done is a filled tick, missed is a cross, pending
/// is an open ring, and each carries a semantic label for screen readers.
///
/// The glyph, the fill and the label are decided here because they are what
/// the status *means*. The tint comes from `StatusColors` because that is what
/// the status merely *looks like*, and the two want changing at different
/// times.
class StatusIndicator extends StatelessWidget {
  const StatusIndicator({
    required this.status,
    this.size = Sizes.statusIndicator,
    super.key,
  });

  final OccurrenceStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final color = colors.forStatus(status);
    final (icon, filled, label) = switch (status) {
      OccurrenceStatus.done => (Icons.check_rounded, true, 'Done'),
      OccurrenceStatus.partial => (Icons.contrast_rounded, false, 'Partial'),
      OccurrenceStatus.missed => (Icons.close_rounded, false, 'Missed'),
      OccurrenceStatus.skipped => (Icons.remove_rounded, false, 'Skipped'),
      OccurrenceStatus.paused => (Icons.pause_rounded, false, 'Paused'),
      OccurrenceStatus.notScheduled => (
          Icons.remove_rounded,
          false,
          'Not scheduled',
        ),
      OccurrenceStatus.pending => (null, false, 'Not done yet'),
    };

    return Semantics(
      label: label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? color : Colors.transparent,
          border: Border.all(
            color: color,
            width: filled ? 0 : 2,
          ),
        ),
        child: icon == null
            ? null
            : Icon(
                icon,
                size: size * Sizes.indicatorGlyphRatio,
                color: filled ? colors.onDone : color,
              ),
      ),
    );
  }
}
