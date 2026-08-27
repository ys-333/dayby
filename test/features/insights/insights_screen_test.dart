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

  group('data thresholds', () {
    testWidgets('a young commitment gets an honest empty state',
        (tester) async {
      // Started eight days ago: nowhere near the 21-observation floor.
      await commitment(from: d(2026, 8, 20));
      await h.pump(tester, const InsightsScreen());

      expect(find.text('Not enough data yet'), findsOneWidget);
      expect(find.textContaining('Keep tracking'), findsOneWidget);
    });

    testWidgets('no history at all still renders without inventing numbers',
        (tester) async {
      await h.pump(tester, const InsightsScreen());
      expect(find.text('Not enough data yet'), findsOneWidget);
      // Consistency with nothing eligible is an em dash, never 0%.
      expect(find.text('—'), findsWidgets);
      expect(find.text('0%'), findsNothing);
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
