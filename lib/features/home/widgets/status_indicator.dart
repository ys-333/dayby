import 'package:flutter/material.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';

/// Renders a status with a distinct **shape and glyph**, never colour alone.
///
/// Colour is an accent here, not the signal. Roughly one in twelve men has some
/// colour-vision deficiency, and a tracker whose entire meaning is red-vs-green
/// is unreadable to them — so done is a filled tick, missed is a cross, pending
/// is an open ring, and each carries a semantic label for screen readers.
class StatusIndicator extends StatelessWidget {
  const StatusIndicator({
    required this.status,
    this.size = 28,
    super.key,
  });

  final OccurrenceStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, filled, color, label) = switch (status) {
      OccurrenceStatus.done => (
          Icons.check_rounded,
          true,
          scheme.primary,
          'Done',
        ),
      OccurrenceStatus.partial => (
          Icons.contrast_rounded,
          false,
          scheme.tertiary,
          'Partial',
        ),
      OccurrenceStatus.missed => (
          Icons.close_rounded,
          false,
          scheme.error,
          'Missed',
        ),
      OccurrenceStatus.skipped => (
          Icons.remove_rounded,
          false,
          scheme.outline,
          'Skipped',
        ),
      OccurrenceStatus.paused => (
          Icons.pause_rounded,
          false,
          scheme.outline,
          'Paused',
        ),
      OccurrenceStatus.notScheduled => (
          Icons.remove_rounded,
          false,
          scheme.outline,
          'Not scheduled',
        ),
      OccurrenceStatus.pending => (
          null,
          false,
          scheme.outlineVariant,
          'Not done yet',
        ),
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
                size: size * 0.62,
                color: filled ? scheme.onPrimary : color,
              ),
      ),
    );
  }
}
