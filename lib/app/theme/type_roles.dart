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
}
