import 'package:flutter/material.dart';
import 'package:riyaz/domain/analytics/day_band.dart';

/// Fill, ring and ink for one calendar cell.
@immutable
class BandStyle {
  const BandStyle({
    required this.fill,
    required this.border,
    required this.ink,
  });

  final Color fill;
  final Color border;
  final Color ink;

  static BandStyle lerp(BandStyle a, BandStyle b, double t) => BandStyle(
        fill: Color.lerp(a.fill, b.fill, t)!,
        border: Color.lerp(a.border, b.border, t)!,
        ink: Color.lerp(a.ink, b.ink, t)!,
      );
}

/// How each [DayBand] paints on a calendar.
///
/// A calendar is scanned rather than read, so a band is carried by fill and
/// shape first — solid, filled-with-a-ring, bare ring, faint outline — and
/// tinted second. That ordering is why this is a small ramp of styles rather
/// than a list of colours: swapping the palette must not be able to
/// accidentally delete the shape distinction that makes the grid legible
/// without colour at all.
///
/// As with `StatusColors`, every value here is still derived from the
/// [ColorScheme] the widgets used to read directly. Same pixels, one place to
/// change them.
@immutable
class BandColors extends ThemeExtension<BandColors> {
  const BandColors({
    required this.strong,
    required this.partial,
    required this.weak,
    required this.none,
    required this.future,
    required this.todayRing,
  });

  factory BandColors.from(ColorScheme scheme) => BandColors(
        strong: BandStyle(
          fill: scheme.primary,
          border: scheme.primary,
          ink: scheme.onPrimary,
        ),
        partial: BandStyle(
          fill: scheme.primaryContainer,
          border: scheme.primary,
          ink: scheme.onPrimaryContainer,
        ),
        weak: BandStyle(
          fill: Colors.transparent,
          border: scheme.error,
          ink: scheme.onSurface,
        ),
        none: BandStyle(
          fill: Colors.transparent,
          border: scheme.outlineVariant,
          ink: scheme.onSurfaceVariant,
        ),
        // A day that has not happened cannot have been failed: faintest
        // outline, never a fill, never an error colour.
        future: BandStyle(
          fill: Colors.transparent,
          border: scheme.outlineVariant.withValues(alpha: 0.4),
          ink: scheme.outline,
        ),
        todayRing: scheme.tertiary,
      );

  final BandStyle strong;
  final BandStyle partial;
  final BandStyle weak;
  final BandStyle none;
  final BandStyle future;

  /// The ring that marks today, whatever band it happens to be in.
  final Color todayRing;

  BandStyle forBand(DayBand band) => switch (band) {
        DayBand.strong => strong,
        DayBand.partial => partial,
        DayBand.weak => weak,
        DayBand.none => none,
        DayBand.future => future,
      };

  @override
  BandColors copyWith({
    BandStyle? strong,
    BandStyle? partial,
    BandStyle? weak,
    BandStyle? none,
    BandStyle? future,
    Color? todayRing,
  }) =>
      BandColors(
        strong: strong ?? this.strong,
        partial: partial ?? this.partial,
        weak: weak ?? this.weak,
        none: none ?? this.none,
        future: future ?? this.future,
        todayRing: todayRing ?? this.todayRing,
      );

  @override
  BandColors lerp(BandColors? other, double t) {
    if (other == null) return this;
    return BandColors(
      strong: BandStyle.lerp(strong, other.strong, t),
      partial: BandStyle.lerp(partial, other.partial, t),
      weak: BandStyle.lerp(weak, other.weak, t),
      none: BandStyle.lerp(none, other.none, t),
      future: BandStyle.lerp(future, other.future, t),
      todayRing: Color.lerp(todayRing, other.todayRing, t)!,
    );
  }
}
