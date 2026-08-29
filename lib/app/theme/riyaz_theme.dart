import 'package:flutter/material.dart';

import 'band_colors.dart';
import 'palette.dart';
import 'status_colors.dart';

/// Builds the app theme for [brightness].
///
/// Both themes come from one function so that light and dark cannot drift
/// apart by being edited separately — the failure that makes a dark mode feel
/// like an afterthought. Each reads its values from [Palette].
///
/// The `ColorScheme` is generated and then overridden rather than written out
/// in full: the roles below are the ones the app actually paints with, and
/// letting Material derive the rest keeps every unlisted role internally
/// consistent instead of guessed at.
ThemeData riyazTheme(Brightness brightness) {
  final p = Palette.of(brightness);
  final scheme = ColorScheme.fromSeed(
    seedColor: p.sage,
    brightness: brightness,
  ).copyWith(
    surface: p.ground,
    onSurface: p.ink,
    onSurfaceVariant: p.ink2,
    surfaceContainerLowest: p.ground,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.raised,
    surfaceContainerHighest: p.raised,
    primary: p.sage,
    onPrimary: p.ground,
    primaryContainer: p.heat[1],
    onPrimaryContainer: p.ink,
    secondary: p.ochre,
    onSecondary: p.ground,
    tertiary: p.ochre,
    onTertiary: p.ground,
    error: p.clay,
    onError: p.ground,
    errorContainer: p.surface,
    onErrorContainer: p.ink,
    outline: p.ink3,
    outlineVariant: p.line,
  );

  final base = ThemeData(brightness: brightness, colorScheme: scheme);

  return base.copyWith(
    scaffoldBackgroundColor: p.ground,
    dividerColor: p.line,
    textTheme: _textTheme(base.textTheme, p),
    extensions: <ThemeExtension<dynamic>>[
      StatusColors.from(p),
      BandColors.from(p),
    ],
  );
}

/// Type sized for a list you glance at, not a document you read.
///
/// Every line height is a **multiplier**, never a fixed pixel box.
/// `polish_test.dart` renders every screen at 1.8× text scale, and a
/// hard-coded line box is exactly how that test found a 441px overflow.
TextTheme _textTheme(TextTheme base, Palette p) =>
    base.apply(bodyColor: p.ink, displayColor: p.ink).copyWith(
          titleMedium: base.titleMedium?.copyWith(
            fontSize: 16,
            height: 1.3,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
            color: p.ink,
          ),
          bodySmall: base.bodySmall?.copyWith(
            fontSize: 13,
            height: 1.35,
            color: p.ink2,
            // Counts stack in a column down the list, so the digits have to
            // line up. Tabular figures only where that is actually true —
            // elsewhere they just look mechanical.
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          labelSmall: base.labelSmall?.copyWith(
            height: 1.3,
            letterSpacing: 1.1,
            color: p.ink3,
          ),
        );

/// Reaching the app's colour vocabularies from a widget.
extension RiyazThemeAccess on BuildContext {
  /// Status colours, falling back to the palette for this brightness when no
  /// app theme is installed.
  ///
  /// The fallback exists for a bare `MaterialApp` — widget tests and previews.
  /// It resolves the *same* values the theme registers, so a screen renders
  /// identically either way, and `palette_test.dart` pins that equivalence so
  /// the two cannot drift apart unnoticed.
  StatusColors get statusColors {
    final theme = Theme.of(this);
    return theme.extension<StatusColors>() ?? StatusColors.of(theme.brightness);
  }

  /// Calendar band styles. Same fallback contract as [statusColors].
  BandColors get bandColors {
    final theme = Theme.of(this);
    return theme.extension<BandColors>() ?? BandColors.of(theme.brightness);
  }

  /// The raw palette, for the few places that need a value no role covers.
  Palette get palette => Palette.of(Theme.of(this).brightness);
}
