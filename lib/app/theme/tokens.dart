/// Numeric design tokens: the sizes and gaps the UI is allowed to use.
///
/// These are deliberately the values already on screen, oddities included —
/// this layer names them, it does not regularise them. A row's 14dp vertical
/// padding sits beside a 16dp horizontal one because that is what shipped, and
/// tidying the scale is a change to how the app *looks*, which belongs in the
/// commit that changes how the app looks. Naming them first means that commit
/// is a diff of values in one file rather than a hunt through every widget.
library;

/// Padding and gaps.
abstract final class Insets {
  /// Horizontal padding on a full-width row.
  static const double rowH = 16;

  /// Vertical padding on a full-width row.
  static const double rowV = 14;

  /// Between a row's leading glyph and its text block.
  static const double rowGap = 14;

  /// Between a row's text block and its trailing control.
  static const double rowTrailingGap = 12;

  /// Between a title and the line beneath it.
  static const double titleGap = 2;
}

/// Corner radii.
abstract final class Radii {
  /// A tappable row.
  static const double row = 14;
}

/// Fixed component sizes.
abstract final class Sizes {
  /// The smallest a tappable thing may ever be.
  ///
  /// Material's `androidTapTargetGuideline` is 48×48 and
  /// `test/polish/polish_test.dart` asserts it on every interactive element.
  /// Any row padding or cell size chosen here has to leave the hit target at
  /// or above this, so the number lives where it can be pointed at rather
  /// than rediscovered by a failing test.
  static const double minTapTarget = 48;

  /// The smallest a commitment row may be.
  ///
  /// Above [minTapTarget] on purpose. The floor is what a finger needs; this
  /// is what a list needs to feel unhurried rather than crammed, which is the
  /// difference between an app you open daily and one you avoid.
  static const double rowMinHeight = 52;

  /// The status circle on a commitment row.
  static const double statusIndicator = 28;

  /// A day cell in the month calendar.
  static const double calendarCell = 34;

  /// Glyph size relative to the circle enclosing it.
  static const double indicatorGlyphRatio = 0.62;
}
