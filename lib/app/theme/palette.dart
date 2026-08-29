import 'package:flutter/material.dart';

/// The raw colour values. Nothing outside this file should name a hex code.
///
/// Two full palettes rather than one seed run through Material's generator.
/// A generated scheme optimises for its own internal harmony and has no
/// opinion about what any colour *means*, which is how the app ended up
/// painting a missed run in the same red a form uses for an invalid field.
///
/// ## Everything here is measured, not judged by eye
///
/// Every value was solved against the **worst surface it can land on** — the
/// lightest one in dark mode (`raised`), the darkest one in light (`surface`)
/// — because a mark that clears 4.5:1 on the page background can quietly fail
/// on a card. Checking against the page background alone is what made an
/// earlier draft of this palette look verified when it was not.
///
/// The floors, all enforced by `test/app/theme/palette_test.dart`:
///
/// * text and glyphs — 4.5:1 (WCAG AA)
/// * rings, dots and fills that carry meaning — 3:1 (non-text contrast)
/// * adjacent heat-ramp steps — 1.45:1, so the ramp reads as steps
/// * the three status hues — OKLab ΔE ≥ 6 under normal, protan, deutan and
///   tritan vision
///
/// ## Why the status hues sit where they do
///
/// Sage, ochre and clay are close in hue, and an earlier arrangement put all
/// three at nearly the same lightness — which reads fine to full colour
/// vision and collapses to ΔE 3.0 under deuteranopia, where "partial" and
/// "missed" become the same brown. They are now an evenly spaced lightness
/// ladder, which is what carries them under simulation: worst-case ΔE is 9.8
/// in dark and 8.0 in light.
///
/// The ladder runs in the direction the statuses mean. Done is the most
/// prominent against the page, partial next, missed the quietest — the
/// opposite of what an optimiser picks if you only ask it for separation, and
/// the whole point of the redesign. A miss should be legible, not loud.
@immutable
class Palette {
  const Palette({
    required this.ground,
    required this.surface,
    required this.raised,
    required this.line,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.sage,
    required this.ochre,
    required this.clay,
    required this.pendingRing,
    required this.futureRing,
    required this.notScheduled,
    required this.heat,
  });

  /// The page.
  final Color ground;

  /// A grouped band or card on the page.
  final Color surface;

  /// The most prominent card. The worst case for contrast in dark mode.
  final Color raised;

  /// Hairline separators. Decorative — deliberately below any text floor.
  final Color line;

  /// Primary text.
  final Color ink;

  /// Secondary text.
  final Color ink2;

  /// Tertiary text, and the smallest text that ships.
  final Color ink3;

  /// Done.
  final Color sage;

  /// Partial.
  final Color ochre;

  /// Missed. Quietest of the three on purpose.
  final Color clay;

  /// An open ring for an occurrence that has not resolved.
  final Color pendingRing;

  /// A day that has not happened. Recessive to the point of near-invisibility,
  /// and never a text or meaning-bearing colour — it is the absence of a mark.
  final Color futureRing;

  /// The schedule expected nothing here.
  final Color notScheduled;

  /// Sequential ramp, none → strongest, for calendars and heat grids.
  ///
  /// Five steps because a scanned grid needs distinguishable states, not a
  /// continuum. `heat[0]` is "nothing tracked" and is the boundary that
  /// carries the most meaning, so it gets the widest gap to its neighbour.
  ///
  /// The month calendar draws a numeral inside each cell, and only the ends
  /// of this ramp can carry one: a mid-tone fill fails 4.5:1 against both
  /// inks at once, which is the ordinary fate of any middling grey-green. So
  /// the calendar samples `heat[1]` and `heat[4]`. The full ramp is for a
  /// grid with no text in it.
  final List<Color> heat;

  /// Warm near-black. Verified against `raised` (#23201B), the lightest
  /// surface a mark can sit on.
  static const Palette dark = Palette(
    ground: Color(0xFF14120E),
    surface: Color(0xFF1B1915),
    raised: Color(0xFF23201B),
    line: Color(0xFF2C2924),
    ink: Color(0xFFF2EEE6), // 14.03
    ink2: Color(0xFF9E988B), //  5.66
    ink3: Color(0xFF90897B), //  4.68
    sage: Color(0xFFA2C6AD), //  8.67
    ochre: Color(0xFFC7A45A), //  6.87
    clay: Color(0xFFAD7E6C), //  4.62
    pendingRing: Color(0xFF726D62), // 3.15
    futureRing: Color(0xFF38342C), // decorative
    notScheduled: Color(0xFF746C5E), // 3.13
    heat: [
      Color(0xFF26231E),
      Color(0xFF42584A),
      Color(0xFF62836B),
      Color(0xFF87AC91),
      Color(0xFFAED4B8),
    ],
  );

  /// Warm off-white. Verified against `surface` (#F5F2EA), the darkest
  /// surface a mark can sit on.
  static const Palette light = Palette(
    ground: Color(0xFFFBF9F4),
    surface: Color(0xFFF5F2EA),
    raised: Color(0xFFFFFFFF),
    line: Color(0xFFE4DFD3),
    ink: Color(0xFF1E1B16), // 15.34
    ink2: Color(0xFF4A443A), //  8.61
    ink3: Color(0xFF746D5D), //  4.59
    sage: Color(0xFF18462A), //  9.63
    ochre: Color(0xFF6D5100), //  6.64
    clay: Color(0xFF9F5B45), //  4.63
    pendingRing: Color(0xFF847F74), // 3.56
    futureRing: Color(0xFFE9E4D8), // decorative
    notScheduled: Color(0xFF8E897E), // 3.11
    heat: [
      Color(0xFFEFEBE1),
      Color(0xFF85B093),
      Color(0xFF658770),
      Color(0xFF4A6352),
      Color(0xFF18462A),
    ],
  );

  static Palette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// The lightest surface in dark mode, the darkest in light: whichever gives
  /// a mark the least contrast to work against. Tests measure against this.
  Color get worstSurface => ground.computeLuminance() < 0.5 ? raised : surface;
}
