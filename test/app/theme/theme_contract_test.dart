import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/theme/palette.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';

/// The Material roles the app actually leans on, pinned to the palette values
/// they must resolve to.
///
/// This exists instead of migrating thirty-four `colorScheme.onSurfaceVariant`
/// call sites onto a token of their own. Those call sites are *right*:
/// `onSurfaceVariant` is Material's role for de-emphasised text on a surface,
/// which is exactly the question a caption is asking, and rewriting it as
/// `palette.ink2` would swap a semantic role for a palette index — strictly
/// less readable. `StatusColors` and `BandColors` exist because Material has
/// no role for "a missed day" or "a weak week"; it does have one for quiet
/// text.
///
/// What was genuinely missing is any guard on the mapping. Thirty-four widgets
/// trust `onSurfaceVariant` to be `ink2`, and nothing said so. One line in
/// `riyazTheme` could have re-tinted every caption in the app with no test
/// failing anywhere. Now it cannot.
void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    group('$brightness', () {
      final palette = Palette.of(brightness);
      final scheme = riyazTheme(brightness).colorScheme;

      test('quiet text is ink2', () {
        // The most-used role in the app by a wide margin: captions, units,
        // section labels, footnotes, every "of 29 scheduled days".
        expect(scheme.onSurfaceVariant, palette.ink2);
      });

      test('body text is ink and the ground is the ground', () {
        expect(scheme.onSurface, palette.ink);
        expect(scheme.surface, palette.ground);
      });

      test('rules and outlines are the line and ink3', () {
        expect(scheme.outlineVariant, palette.line);
        expect(scheme.outline, palette.ink3);
      });

      test('the accent is sage, and what sits on it is the ground', () {
        expect(scheme.primary, palette.sage);
        expect(scheme.onPrimary, palette.ground);
      });

      test('there is no red anywhere, error included', () {
        // Principle 2 of the design system, and the one most easily lost:
        // `ColorScheme.fromSeed` supplies a real red for `error` unless it is
        // overridden, and a single un-overridden role is enough to put a
        // validation red on a screen that has none.
        expect(scheme.error, palette.clay);
        for (final colour in [
          scheme.error,
          scheme.onError,
          scheme.errorContainer,
          scheme.primary,
          scheme.secondary,
          scheme.tertiary,
          scheme.surface,
          scheme.onSurface,
          scheme.onSurfaceVariant,
        ]) {
          expect(_isRed(colour), isFalse, reason: '$colour reads as red');
        }
      });

      test('the raised surfaces are the raised value', () {
        expect(scheme.surfaceContainerHigh, palette.raised);
        expect(scheme.surfaceContainerHighest, palette.raised);
      });
    });
  }
}

/// A saturated hue in the red sector. Deliberately loose — the point is to
/// catch a stock Material red slipping in, not to police the warm end of the
/// palette, which is where this app lives.
bool _isRed(Color colour) {
  final hsl = HSLColor.fromColor(colour);
  final hue = hsl.hue;
  final inSector = hue < 18 || hue > 345;
  return inSector && hsl.saturation > 0.5 && hsl.lightness > 0.2;
}
