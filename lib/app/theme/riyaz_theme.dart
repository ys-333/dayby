import 'package:flutter/material.dart';

import 'band_colors.dart';
import 'status_colors.dart';

/// The single seed the palette is generated from today.
const Color _seed = Color(0xFF3F6C51);

/// Builds the app theme for [brightness], with the app's own colour
/// vocabularies attached.
///
/// Both `MaterialApp` themes come from one function so that light and dark
/// cannot drift apart by being edited separately — the failure that makes a
/// dark mode feel like an afterthought.
ThemeData riyazTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    extensions: <ThemeExtension<dynamic>>[
      StatusColors.from(scheme),
      BandColors.from(scheme),
    ],
  );
}

/// Reaching the app's colour vocabularies from a widget.
extension RiyazThemeAccess on BuildContext {
  /// Status colours, falling back to the ambient scheme when no app theme is
  /// installed.
  ///
  /// The fallback is for a bare `MaterialApp` — widget tests and previews —
  /// and it is currently *exactly* what [riyazTheme] registers, so a screen
  /// renders the same either way.
  ///
  /// That equivalence stops holding the moment these colours become literal
  /// values rather than scheme lookups. Whoever makes that change has to
  /// change the two fallbacks below in the same commit, or tests will go on
  /// silently rendering the old palette and pass while the app looks
  /// different.
  StatusColors get statusColors {
    final theme = Theme.of(this);
    return theme.extension<StatusColors>() ??
        StatusColors.from(theme.colorScheme);
  }

  /// Calendar band styles. Same fallback contract as [statusColors].
  BandColors get bandColors {
    final theme = Theme.of(this);
    return theme.extension<BandColors>() ?? BandColors.from(theme.colorScheme);
  }
}
