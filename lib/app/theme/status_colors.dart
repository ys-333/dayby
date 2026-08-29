import 'package:flutter/material.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';

import 'palette.dart';

/// The colour each [OccurrenceStatus] wears, in one place.
///
/// Statuses used to borrow Material's UI roles directly — missed took
/// `scheme.error`, partial took `scheme.tertiary`. Those roles mean something
/// else. `error` is the colour of *a form field you filled in wrong*, and
/// pointing it at a morning run you did not go on tells the user their day was
/// invalid. A tracker that greets you with a column of validation failures is
/// the thing this app is trying not to be.
///
/// So statuses have their own vocabulary, drawn from [Palette] rather than
/// from Material's roles. Done is sage, partial ochre, missed clay — and the
/// three run down an evenly spaced lightness ladder in the direction they
/// mean, done most prominent and missed quietest.
///
/// Colour still never carries meaning alone — the shape and glyph in
/// `StatusIndicator` do that, and this only tints them. That is also what
/// licenses hues this close together: the three clear ΔE 6 under every
/// simulated colour vision, but it is the tick, the half-circle and the cross
/// that a reader actually distinguishes.
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

  factory StatusColors.from(Palette p) => StatusColors(
        done: p.sage,
        onDone: p.ground,
        partial: p.ochre,
        missed: p.clay,
        // Skipped and paused are both "this one is out of the reckoning", and
        // they share the recessive neutral. What separates them is the glyph
        // — a dash against a pause bar — not the colour.
        skipped: p.ink3,
        paused: p.ink3,
        notScheduled: p.notScheduled,
        pending: p.pendingRing,
        muted: p.ink3,
      );

  static StatusColors of(Brightness brightness) =>
      StatusColors.from(Palette.of(brightness));

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
