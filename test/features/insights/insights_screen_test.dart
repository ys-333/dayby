import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/features/insights/insights_screen.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/dates.dart';
import '../../support/harness.dart';

/// The patterns section sits at the bottom of a long list, so tests have to
/// scroll it into view before its cards are built.
Future<void> scrollToPatterns(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late Harness h;
  setUp(() => h = Harness());
  tearDown(() => h.dispose());

  Future<String> commitment({
    required CivilDate from,
    String name = 'Running',
    Frequency frequency = const Frequency.daily(),
  }) =>
      h.repo.createCommitment(
        name: name,
        frequency: frequency,
        startedOn: from,
        nowUtc: h.nowUtc,
      );

  Future<void> record(String id, CivilDate date) => h.repo.record(
        commitmentId: id,
        date: date,
        kind: TrackingKind.done,
        nowUtc: h.nowUtc,
        label: 'done',
      );


  /// Patterns sits at the foot of a screen that grew when the momentum
  /// footnote and the consistency denominator landed, and a `ListView` only
  /// builds what is on screen.
  Future<void> scrollToEnd(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
  }

  group('data thresholds', () {
    testWidgets('a young commitment gets an honest empty state',
        (tester) async {
      // Started eight days ago: nowhere near the 21-observation floor.
      await commitment(from: d(2026, 8, 20));
      await h.pump(tester, const InsightsScreen());
      await scrollToEnd(tester);

      expect(find.text('Not enough data yet'), findsOneWidget);
      expect(find.textContaining('Keep tracking'), findsOneWidget);
    });

    testWidgets('no history at all still renders without inventing numbers',
        (tester) async {
      await h.pump(tester, const InsightsScreen());
      await scrollToEnd(tester);
      expect(find.text('Not enough data yet'), findsOneWidget);
      // Consistency with nothing eligible is an em dash, never 0%.
      expect(find.text('—'), findsWidgets);
      expect(find.text('0%'), findsNothing);
    });
  });

  group('what the screen leads with', () {
    /// Six weeks of real behaviour, so every figure has something to report.
    Future<void> seedSixWeeks(WidgetTester tester) async {
      final id = await commitment(from: d(2026, 7, 13));
      for (var i = 0; i < 46; i++) {
        final date = d(2026, 7, 13).plusDays(i);
        if (date > d(2026, 8, 27)) break;
        if (date.weekday == DateTime.sunday) continue;
        await record(id, date);
      }
      await h.pump(tester, const InsightsScreen());
    }

    testWidgets('the current streak is a footnote, never a headline figure',
        (tester) async {
      await seedSixWeeks(tester);

      // CLAUDE.md: "Streaks are shown but are deliberately not the headline
      // metric — long-run consistency and recovery time are." The current
      // streak used to lead Momentum as the largest number on the screen,
      // which is the ordinary habit-tracker failure: a counter that only ever
      // goes to zero, taking the user's motivation with it.
      expect(find.text('Current streak'), findsNothing);
      expect(find.text('A typical run'), findsOneWidget);
      expect(find.text('Your best run'), findsOneWidget);
      expect(find.text('To come back'), findsOneWidget);
      expect(
        find.textContaining(RegExp(r'Currently on day \d+\.|Not on a run')),
        findsOneWidget,
      );
    });

    testWidgets('momentum is worded the same here as on a commitment',
        (tester) async {
      await seedSixWeeks(tester);

      // The two screens report the same three numbers and used to call them
      // different things — "Avg run" here, "A typical run" there.
      expect(find.text('Avg run'), findsNothing);
      expect(find.text('Avg recovery'), findsNothing);
      expect(find.text('Longest'), findsNothing);
    });

    testWidgets('the lead percentage states its own denominator',
        (tester) async {
      await seedSixWeeks(tester);

      // A percentage with no stated base cannot be argued with, and this one
      // has a base most people would guess wrong: skips, pauses, unscheduled
      // days and anything pending are already out of it.
      expect(
        find.textContaining(
          RegExp(r'Of \d+ occurrences that were yours to make'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('skipped is marked as outside the score', (tester) async {
      final id = await commitment(from: d(2026, 7, 13));
      for (var i = 0; i < 40; i++) {
        await record(id, d(2026, 7, 13).plusDays(i));
      }
      await h.repo.record(
        commitmentId: id,
        date: d(2026, 8, 26),
        kind: TrackingKind.skipped,
        nowUtc: h.nowUtc,
        label: 'skip',
      );
      await h.pump(tester, const InsightsScreen());

      // Not a fourth outcome beside Done, Partial and Missed. It never
      // entered the denominator, and the row has to say so.
      expect(find.text('Skipped, not counted'), findsOneWidget);
      expect(find.text('Skipped'), findsNothing);
    });

    testWidgets('the trend has a scale you can read a value off',
        (tester) async {
      await seedSixWeeks(tester);

      // The chart used to be a line between two bare rules: you could see the
      // shape and not read a single value off it.
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(find.textContaining('Last 90 days'), findsOneWidget);
      expect(find.textContaining('now · '), findsOneWidget);
    });
  });

  group('patterns', () {
    testWidgets('names the weakest weekday once the gap is real',
        (tester) async {
      // Six weeks, every day done except Sundays.
      final id = await commitment(from: d(2026, 7, 13));
      for (var i = 0; i < 46; i++) {
        final date = d(2026, 7, 13).plusDays(i);
        if (date > d(2026, 8, 27)) break;
        if (date.weekday == DateTime.sunday) continue;
        await record(id, date);
      }
      await h.pump(tester, const InsightsScreen());
      await scrollToPatterns(tester);

      expect(find.text('Not enough data yet'), findsNothing);
      expect(find.textContaining('Sunday is your weakest day'), findsOneWidget);
    });

    testWidgets('reports momentum after repeated cycles', (tester) async {
      // Four cycles of five done, two missed.
      final id = await commitment(from: d(2026, 7, 1));
      var cursor = d(2026, 7, 1);
      for (var cycle = 0; cycle < 6; cycle++) {
        for (var i = 0; i < 5; i++) {
          if (cursor <= d(2026, 8, 27)) await record(id, cursor);
          cursor = cursor.plusDays(1);
        }
        cursor = cursor.plusDays(2);
      }
      await h.pump(tester, const InsightsScreen());
      await scrollToPatterns(tester);

      expect(find.textContaining('Your runs last about'), findsOneWidget);
      expect(find.textContaining('You come back within'), findsOneWidget);
    });
  });

  group('commitment load', () {
    testWidgets('warns past six active daily commitments', (tester) async {
      for (var i = 0; i < 6; i++) {
        await commitment(from: d(2026, 8, 1), name: 'Daily $i');
      }
      await h.pump(tester, const InsightsScreen());
      await scrollToPatterns(tester);

      expect(find.textContaining('active daily commitments'), findsOneWidget);
      expect(find.textContaining('That is a lot to hold'), findsOneWidget);
    });

    testWidgets('the load card is not dressed as an error', (tester) async {
      for (var i = 0; i < 6; i++) {
        await commitment(from: d(2026, 8, 1), name: 'Daily $i');
      }
      await h.pump(tester, const InsightsScreen());
      await scrollToPatterns(tester);

      final context = tester.element(find.byType(InsightsScreen));
      final scheme = Theme.of(context).colorScheme;

      // It used to take `errorContainer` and a warning triangle, which is the
      // livery of a form filled in wrong. Having eleven daily commitments is
      // something the user chose, and the app has an opinion about it, not a
      // complaint.
      final cards = tester.widgetList<Card>(find.byType(Card));
      expect(cards, isNotEmpty);
      for (final card in cards) {
        expect(
          card.color,
          anyOf(isNull, isNot(scheme.errorContainer)),
          reason: 'no insight card paints itself as an error',
        );
      }

      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.byIcon(Icons.layers_rounded), findsOneWidget);

      final icon = tester.widget<Icon>(
        find.byIcon(Icons.layers_rounded),
      );
      expect(icon.color, scheme.onSurfaceVariant);
      expect(icon.color, isNot(scheme.error));
      expect(icon.color, isNot(scheme.onErrorContainer));
    });

    testWidgets('stays quiet below the cap', (tester) async {
      for (var i = 0; i < 5; i++) {
        await commitment(from: d(2026, 8, 1), name: 'Daily $i');
      }
      await h.pump(tester, const InsightsScreen());
      expect(find.textContaining('active daily commitments'), findsNothing);
    });

    testWidgets('period commitments do not count toward the daily cap',
        (tester) async {
      for (var i = 0; i < 6; i++) {
        await commitment(
          from: d(2026, 8, 1),
          name: 'Weekly $i',
          frequency: const Frequency.timesPerWeek(target: 3),
        );
      }
      await h.pump(tester, const InsightsScreen());
      expect(find.textContaining('active daily commitments'), findsNothing);
    });
  });

  group('year view', () {
    testWidgets('renders months from rollups', (tester) async {
      final id = await commitment(from: d(2026, 7, 1));
      for (var i = 0; i < 20; i++) {
        await record(id, d(2026, 7, 1).plusDays(i));
      }
      await h.pump(tester, const InsightsScreen());

      expect(find.text('2026'), findsOneWidget);
      expect(find.text('Jul'), findsOneWidget);
      expect(find.text('Aug'), findsOneWidget);
    });
  });
}
