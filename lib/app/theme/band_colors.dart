import 'package:flutter/material.dart';
import 'package:riyaz/domain/analytics/day_band.dart';

import 'palette.dart';

/// Fill, ring and ink for one calendar cell.
@immutable
class BandStyle {
  const BandStyle({
    required this.fill,
    required this.border,
    required this.ink,
    this.width = 1.5,
  });

  final Color fill;
  final Color border;
  final Color ink;

  /// Ring weight. Carries meaning, so it is part of the token rather than a
  /// number the widget picks.
  final double width;

  static BandStyle lerp(BandStyle a, BandStyle b, double t) => BandStyle(
        fill: Color.lerp(a.fill, b.fill, t)!,
        border: Color.lerp(a.border, b.border, t)!,
        ink: Color.lerp(a.ink, b.ink, t)!,
        width: a.width + (b.width - a.width) * t,
      );
}

/// How each [DayBand] paints on a calendar.
///
/// A calendar is scanned rather than read, so a band is carried by fill and
/// shape first — solid, filled, bare ring, faint outline — and tinted second.
///
/// The pairing that needed fixing: a weak day and an empty day were both a
/// transparent circle, separated by ring *colour alone*. That is the one thing
/// this app is not allowed to do. They are now separated by ring weight as
/// well, so a day with misses in it reads as a heavier outline whether or not
/// the reader can tell clay from a warm grey.
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

  factory BandColors.from(Palette p) => BandColors(
        // The two ends of the heat ramp: the only steps that can carry a
        // legible numeral. See Palette.heat.
        strong: BandStyle(fill: p.heat[4], border: p.heat[4], ink: p.ground),
        partial: BandStyle(fill: p.heat[1], border: p.heat[1], ink: p.ink),
        weak: BandStyle(
          fill: Colors.transparent,
          border: p.clay,
          ink: p.ink2,
          width: 2.5,
        ),
        none: BandStyle(
          fill: Colors.transparent,
          border: p.line,
          ink: p.ink3,
          width: 1,
        ),
        // A day that has not happened cannot have been failed: faintest
        // outline, never a fill, never the missed colour. The numeral stays
        // fully legible — a future day is unknown, not unimportant.
        future: BandStyle(
          fill: Colors.transparent,
          border: p.futureRing,
          ink: p.ink3,
          width: 1,
        ),
        // Deliberately not ochre. Today is not a status, and borrowing
        // partial's hue for it is the same category error this whole layer
        // exists to undo.
        todayRing: p.ink2,
      );

  static BandColors of(Brightness brightness) =>
      BandColors.from(Palette.of(brightness));

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
