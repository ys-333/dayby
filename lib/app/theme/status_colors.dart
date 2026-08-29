import 'package:flutter/material.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';

/// The colour each [OccurrenceStatus] wears, in one place.
///
/// Statuses used to borrow Material's UI roles directly — missed took
/// `scheme.error`, partial took `scheme.tertiary`. Those roles mean something
/// else. `error` is the colour of *a form field you filled in wrong*, and
/// pointing it at a morning run you did not go on tells the user their day was
/// invalid. A tracker that greets you with a column of validation failures is
/// the thing this app is trying not to be.
///
/// So statuses get their own vocabulary. Nothing here changes what is on
/// screen yet: every value is still wired from the [ColorScheme] it came from,
/// which is what makes the extraction provably pixel-identical. What changes
/// is that there is now a single place to change it.
///
/// Colour still never carries meaning alone — the shape and glyph in
/// `StatusIndicator` do that, and this only tints them.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.done,
    required this.onDone,
    required this.partial,
    required this.missed,
    required this.skipped,
    required this.paused,
    required this.notScheduled,
    required this.pending,
    required this.muted,
  });

  /// Wires every status to the role it wore before this layer existed.
  ///
  /// This factory is the whole no-visual-change guarantee: the extension is
  /// built from the same scheme the call sites used to read, so the pixels are
  /// identical by construction rather than by inspection.
  factory StatusColors.from(ColorScheme scheme) => StatusColors(
        done: scheme.primary,
        onDone: scheme.onPrimary,
        partial: scheme.tertiary,
        missed: scheme.error,
        skipped: scheme.outline,
        paused: scheme.outline,
        notScheduled: scheme.outline,
        pending: scheme.outlineVariant,
        muted: scheme.outline,
      );

  /// Target met.
  final Color done;

  /// Ink on top of a filled [done] mark.
  final Color onDone;

  /// Attempted, short of target.
  final Color partial;

  /// Expected, not done, window closed.
  final Color missed;

  /// Deliberately skipped — a choice, not a failure, and never coloured as one.
  final Color skipped;

  /// Commitment was paused.
  final Color paused;

  /// The schedule expected nothing.
  final Color notScheduled;

  /// Not resolved yet. Covers today, so it must not read as either outcome.
  final Color pending;

  /// Text for a row whose status takes it out of the reckoning.
  final Color muted;

  Color forStatus(OccurrenceStatus status) => switch (status) {
        OccurrenceStatus.done => done,
        OccurrenceStatus.partial => partial,
        OccurrenceStatus.missed => missed,
        OccurrenceStatus.skipped => skipped,
        OccurrenceStatus.paused => paused,
        OccurrenceStatus.notScheduled => notScheduled,
        OccurrenceStatus.pending => pending,
      };

  @override
  StatusColors copyWith({
    Color? done,
    Color? onDone,
    Color? partial,
    Color? missed,
    Color? skipped,
    Color? paused,
    Color? notScheduled,
    Color? pending,
    Color? muted,
  }) =>
      StatusColors(
        done: done ?? this.done,
        onDone: onDone ?? this.onDone,
        partial: partial ?? this.partial,
        missed: missed ?? this.missed,
        skipped: skipped ?? this.skipped,
        paused: paused ?? this.paused,
        notScheduled: notScheduled ?? this.notScheduled,
        pending: pending ?? this.pending,
        muted: muted ?? this.muted,
      );

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    return StatusColors(
      done: Color.lerp(done, other.done, t)!,
      onDone: Color.lerp(onDone, other.onDone, t)!,
      partial: Color.lerp(partial, other.partial, t)!,
      missed: Color.lerp(missed, other.missed, t)!,
      skipped: Color.lerp(skipped, other.skipped, t)!,
      paused: Color.lerp(paused, other.paused, t)!,
      notScheduled: Color.lerp(notScheduled, other.notScheduled, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}
