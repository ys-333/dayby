import 'package:flutter/material.dart';

/// App type roles, named for what they are rather than where Material filed
/// them.
///
/// A widget asking for `titleMedium` is asking a question about Material's
/// taxonomy. A widget asking for `rowTitle` is asking a question about this
/// app, and the answer can then change once, here, instead of in every widget
/// that happened to pick the same Material role for a different reason.
///
/// The list is short on purpose: a role appears the first time a call site
/// migrates onto it, so there is no vocabulary here that nothing speaks.
///
/// One rule for whatever fills these in later — **line height ships as a
/// multiplier, never as a fixed pixel height.** `polish_test.dart` renders
/// every screen at 1.8× text scale, and a hard-coded line box is exactly how
/// that test found a 441px overflow the last time.
extension TypeRoles on TextTheme {
  /// The name of a commitment on a list row.
  TextStyle? get rowTitle => titleMedium;

  /// The count, period or status word under a row title.
  TextStyle? get rowMeta => bodySmall;

  /// The day's headline — the countdown, and the largest type on the screen.
  ///
  /// Regular weight on purpose. It is a sentence about the day, not a figure
  /// to be read at a glance, and bolding it turns a quiet statement into an
  /// announcement.
  TextStyle? get dayHeadline => headlineLarge?.copyWith(
        fontWeight: FontWeight.w400,
      );

  /// A small capitalised label naming a group of rows.
  TextStyle? get sectionOverline => labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
      );

  /// A tally that sits in a column and must not jitter as it changes.
  TextStyle? get tabularMeta => bodyMedium?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// A quiet line of context beneath or beside the content it explains.
  TextStyle? get footnote => bodySmall;
}
