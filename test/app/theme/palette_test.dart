import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/theme/band_colors.dart';
import 'package:riyaz/app/theme/palette.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/app/theme/status_colors.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/analytics/day_band.dart';

/// The accessibility floors, asserted rather than asserted-to.
///
/// These numbers were solved for outside the app, and a palette that is only
/// verified once is verified until the first person nudges a hex code. Keeping
/// the maths here means the next change to a colour either holds the line or
/// fails the build.
///
/// Everything is measured against the **worst surface the mark can land on**
/// — the lightest one in dark mode, the darkest in light. An earlier draft
/// checked against the page background only and looked fine while small text
/// on a card sat at 4.48:1.
void main() {
  group('contrast', () {
    for (final brightness in Brightness.values) {
      final p = Palette.of(brightness);
      final bg = p.worstSurface;
      final name = brightness.name;

      test('$name: text and glyphs clear 4.5:1', () {
        expect(_ratio(p.ink, bg), greaterThanOrEqualTo(4.5), reason: 'ink');
        expect(_ratio(p.ink2, bg), greaterThanOrEqualTo(4.5), reason: 'ink2');
        expect(_ratio(p.ink3, bg), greaterThanOrEqualTo(4.5), reason: 'ink3');
        expect(_ratio(p.sage, bg), greaterThanOrEqualTo(4.5), reason: 'sage');
        expect(_ratio(p.ochre, bg), greaterThanOrEqualTo(4.5), reason: 'ochre');
        expect(_ratio(p.clay, bg), greaterThanOrEqualTo(4.5), reason: 'clay');
      });

      test('$name: meaning-bearing marks clear 3:1', () {
        expect(_ratio(p.pendingRing, bg), greaterThanOrEqualTo(3));
        expect(_ratio(p.notScheduled, bg), greaterThanOrEqualTo(3));
      });

      test('$name: ink stays legible on every fill it is painted on', () {
        final bands = BandColors.from(p);
        for (final entry in {
          'strong': bands.strong,
          'partial': bands.partial,
        }.entries) {
          expect(
            _ratio(entry.value.ink, entry.value.fill),
            greaterThanOrEqualTo(4.5),
            reason: 'day numeral on the ${entry.key} band',
          );
        }
        expect(_ratio(p.ground, p.sage), greaterThanOrEqualTo(4.5),
            reason: 'the tick inside a filled done mark');
      });

      test('$name: the heat ramp reads as steps, widest at the boundary', () {
        final steps = <double>[
          for (var i = 0; i < p.heat.length - 1; i++)
            _ratio(p.heat[i], p.heat[i + 1]),
        ];
        for (var i = 0; i < steps.length; i++) {
          expect(steps[i], greaterThanOrEqualTo(1.45), reason: 'step $i');
        }
        // heat[0] is "nothing tracked". The jump out of it separates "no data"
        // from "some data", which is a difference of kind, not of degree.
        expect(steps.first, greaterThanOrEqualTo(steps[1]));
      });

      test('$name: prominence follows meaning, done loudest, missed quietest',
          () {
        final done = _ratio(p.sage, p.ground);
        final partial = _ratio(p.ochre, p.ground);
        final missed = _ratio(p.clay, p.ground);
        expect(done, greaterThan(partial));
        expect(partial, greaterThan(missed));
      });
    }
  });

  group('colour-vision deficiency', () {
    // Status colour never carries meaning alone — the glyph does — so the
    // floor here is the 6.0 that is permissible *with* secondary encoding
    // rather than the 8.0 wanted of a bare categorical palette. Both palettes
    // sit at or above 8 anyway; the looser floor is so a future adjustment
    // fails for a real reason rather than on a rounding boundary.
    for (final brightness in Brightness.values) {
      test('${brightness.name}: the three statuses stay apart under '
          'protanopia, deuteranopia and tritanopia', () {
        final p = Palette.of(brightness);
        final pairs = {
          'done/partial': [p.sage, p.ochre],
          'done/missed': [p.sage, p.clay],
          'partial/missed': [p.ochre, p.clay],
        };
        for (final entry in pairs.entries) {
          final worst = _worstDeltaE(entry.value[0], entry.value[1]);
          expect(worst, greaterThanOrEqualTo(6.0),
              reason: '${entry.key} in ${brightness.name} is ΔE $worst');
        }
      });
    }
  });

  group('theme wiring', () {
    for (final brightness in Brightness.values) {
      final theme = riyazTheme(brightness);
      final p = Palette.of(brightness);

      test('${brightness.name}: both vocabularies are registered', () {
        expect(theme.extension<StatusColors>(), isNotNull);
        expect(theme.extension<BandColors>(), isNotNull);
      });

      test('${brightness.name}: statuses resolve to the palette', () {
        final c = theme.extension<StatusColors>()!;
        expect(c.forStatus(OccurrenceStatus.done), p.sage);
        expect(c.forStatus(OccurrenceStatus.partial), p.ochre);
        expect(c.forStatus(OccurrenceStatus.missed), p.clay);
        expect(c.forStatus(OccurrenceStatus.pending), p.pendingRing);
        expect(c.onDone, p.ground);
      });

      test('${brightness.name}: a future day is never filled and never wears '
          'the missed colour', () {
        final future = theme.extension<BandColors>()!.forBand(DayBand.future);
        expect(future.fill, Colors.transparent);
        expect(future.border, isNot(p.clay));
        expect(future.ink, isNot(p.clay));
      });

      test('${brightness.name}: weak and none differ by more than colour', () {
        final bands = theme.extension<BandColors>()!;
        expect(bands.weak.width, isNot(bands.none.width));
      });

      test('${brightness.name}: today is not tinted as a status', () {
        final bands = theme.extension<BandColors>()!;
        expect(bands.todayRing, isNot(p.ochre));
        expect(bands.todayRing, isNot(p.sage));
        expect(bands.todayRing, isNot(p.clay));
      });
    }
  });

  testWidgets('the fallback resolves exactly what the theme registers',
      (tester) async {
    for (final brightness in Brightness.values) {
      late StatusColors bare;
      late BandColors bareBands;
      await tester.pumpWidget(
        MaterialApp(
          // Keyed per brightness: without it the element is reused between
          // iterations, the builder never re-runs, and the second pass
          // silently re-asserts the first one's values.
          key: ValueKey(brightness),
          // No app theme: only the ambient brightness, as a widget test or a
          // preview supplies it.
          theme: ThemeData(brightness: brightness),
          home: Builder(
            builder: (context) {
              bare = context.statusColors;
              bareBands = context.bandColors;
              return const SizedBox();
            },
          ),
        ),
      );

      final theme = riyazTheme(brightness);
      final registered = theme.extension<StatusColors>()!;
      final registeredBands = theme.extension<BandColors>()!;

      for (final status in OccurrenceStatus.values) {
        expect(bare.forStatus(status), registered.forStatus(status),
            reason: '$status in ${brightness.name}');
      }
      expect(bare.onDone, registered.onDone);
      for (final band in DayBand.values) {
        expect(bareBands.forBand(band).fill, registeredBands.forBand(band).fill,
            reason: '$band in ${brightness.name}');
        expect(bareBands.forBand(band).border,
            registeredBands.forBand(band).border);
      }
    }
  });
}

// --- WCAG relative luminance -------------------------------------------------

double _channel(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double _ratio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

// --- OKLab ΔE under simulated colour vision ---------------------------------

/// Machado, Oliveira & Fernandes (2009), severity 1.0.
const Map<String, List<List<double>>> _cvd = {
  'protan': [
    [0.152286, 1.052583, -0.204868],
    [0.114503, 0.786281, 0.099216],
    [-0.003882, -0.048116, 1.051998],
  ],
  'deutan': [
    [0.367322, 0.860646, -0.227968],
    [0.280085, 0.672501, 0.047413],
    [-0.011820, 0.042940, 0.968881],
  ],
  'tritan': [
    [1.255528, -0.076749, -0.178779],
    [-0.078411, 0.930809, 0.147602],
    [0.004733, 0.691367, 0.303900],
  ],
};

List<double> _linear(Color c) => [_channel(c.r), _channel(c.g), _channel(c.b)];

List<double> _simulate(List<double> rgb, String kind) {
  final m = _cvd[kind]!;
  return [
    for (final row in m)
      math.max(
        0.0,
        math.min(1.0, row[0] * rgb[0] + row[1] * rgb[1] + row[2] * rgb[2]),
      ),
  ];
}

List<double> _oklab(List<double> rgb) {
  final l = math.pow(
      0.4122214708 * rgb[0] + 0.5363325363 * rgb[1] + 0.0514459929 * rgb[2],
      1 / 3);
  final m = math.pow(
      0.2119034982 * rgb[0] + 0.6806995451 * rgb[1] + 0.1073969566 * rgb[2],
      1 / 3);
  final s = math.pow(
      0.0883024619 * rgb[0] + 0.2817188376 * rgb[1] + 0.6299787005 * rgb[2],
      1 / 3);
  return [
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  ];
}

double _deltaE(Color a, Color b, String? kind) {
  final x = _oklab(kind == null ? _linear(a) : _simulate(_linear(a), kind));
  final y = _oklab(kind == null ? _linear(b) : _simulate(_linear(b), kind));
  return 100 *
      math.sqrt(math.pow(x[0] - y[0], 2) +
          math.pow(x[1] - y[1], 2) +
          math.pow(x[2] - y[2], 2));
}

double _worstDeltaE(Color a, Color b) => [null, 'protan', 'deutan', 'tritan']
    .map((k) => _deltaE(a, b, k))
    .reduce(math.min);
