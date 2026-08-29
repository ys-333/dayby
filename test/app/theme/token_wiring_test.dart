import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/theme/band_colors.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/app/theme/status_colors.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/analytics/day_band.dart';

/// Pins the token layer to the roles it replaced.
///
/// Extracting these colours was supposed to change nothing on screen, and the
/// widget tests cannot prove that on their own: they pump a bare `MaterialApp`
/// and so exercise the *fallback* in `RiyazThemeAccess`, never the extension
/// the real app registers. Passing tests would therefore survive the two
/// drifting apart — the app rendering one palette while every test rendered
/// another, quietly, for as long as nobody looked at a phone.
///
/// So the invariant is asserted directly, on both paths: whatever supplies the
/// theme, a status wears the scheme role it wore before this layer existed.
/// When those roles are replaced by real values, these expectations are what
/// has to be rewritten — deliberately, in that commit, rather than discovered
/// afterwards.
void main() {
  for (final brightness in Brightness.values) {
    group('${brightness.name} theme', () {
      final theme = riyazTheme(brightness);
      final scheme = theme.colorScheme;

      test('registers both colour vocabularies', () {
        expect(theme.extension<StatusColors>(), isNotNull);
        expect(theme.extension<BandColors>(), isNotNull);
      });

      test('every status keeps the role it had before extraction', () {
        final colors = theme.extension<StatusColors>()!;
        expect(colors.forStatus(OccurrenceStatus.done), scheme.primary);
        expect(colors.forStatus(OccurrenceStatus.partial), scheme.tertiary);
        expect(colors.forStatus(OccurrenceStatus.missed), scheme.error);
        expect(colors.forStatus(OccurrenceStatus.skipped), scheme.outline);
        expect(colors.forStatus(OccurrenceStatus.paused), scheme.outline);
        expect(colors.forStatus(OccurrenceStatus.notScheduled), scheme.outline);
        expect(colors.forStatus(OccurrenceStatus.pending), scheme.outlineVariant);
        expect(colors.onDone, scheme.onPrimary);
        expect(colors.muted, scheme.outline);
      });

      test('every calendar band keeps its fill, ring and ink', () {
        final bands = theme.extension<BandColors>()!;

        expect(bands.forBand(DayBand.strong).fill, scheme.primary);
        expect(bands.forBand(DayBand.strong).ink, scheme.onPrimary);

        expect(bands.forBand(DayBand.partial).fill, scheme.primaryContainer);
        expect(bands.forBand(DayBand.partial).border, scheme.primary);

        expect(bands.forBand(DayBand.weak).fill, Colors.transparent);
        expect(bands.forBand(DayBand.weak).border, scheme.error);

        expect(bands.forBand(DayBand.none).border, scheme.outlineVariant);
        expect(bands.todayRing, scheme.tertiary);
      });

      test('a future day is never filled and never wears the missed colour',
          () {
        final bands = theme.extension<BandColors>()!;
        final future = bands.forBand(DayBand.future);
        final missed = theme.extension<StatusColors>()!.missed;

        expect(future.fill, Colors.transparent);
        expect(future.border, isNot(missed));
        expect(future.ink, isNot(missed));
      });
    });
  }

  testWidgets('the fallback follows the same rule as the registered extension',
      (tester) async {
    late StatusColors withTheme;
    late StatusColors withoutTheme;
    late ColorScheme themedScheme;
    late ColorScheme bareScheme;

    Widget probe(void Function(BuildContext) capture, {ThemeData? theme}) =>
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              capture(context);
              return const SizedBox();
            },
          ),
        );

    await tester.pumpWidget(probe(
      (context) {
        withTheme = context.statusColors;
        themedScheme = Theme.of(context).colorScheme;
      },
      theme: riyazTheme(Brightness.light),
    ));

    await tester.pumpWidget(probe((context) {
      withoutTheme = context.statusColors;
      bareScheme = Theme.of(context).colorScheme;
    }));

    // Different schemes, so different colours — the point is that both resolve
    // a status to the *same role* of whatever scheme is in scope. A fallback
    // updated out of step with the extension breaks exactly here.
    expect(withTheme.missed, themedScheme.error);
    expect(withoutTheme.missed, bareScheme.error);
    expect(withTheme.done, themedScheme.primary);
    expect(withoutTheme.done, bareScheme.primary);
  });
}
