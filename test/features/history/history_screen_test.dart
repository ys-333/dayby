import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/analytics/day_band.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/features/history/history_screen.dart';
import 'package:riyaz/features/history/widgets/calendar_cell.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/dates.dart';
import '../../support/harness.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late Harness h;
  setUp(() => h = Harness());
  tearDown(() => h.dispose());

  Future<String> daily(String name) => h.repo.createCommitment(
        name: name,
        frequency: const Frequency.daily(),
        startedOn: d(2026, 8, 1),
        nowUtc: h.nowUtc,
      );

  CalendarCell cellFor(WidgetTester tester, int day) => tester
      .widgetList<CalendarCell>(find.byType(CalendarCell))
      .firstWhere((c) => c.day.date == d(2026, 8, day));

  group('month calendar', () {
    testWidgets('renders whole weeks and marks the month', (tester) async {
      await daily('Running');
      await h.pump(tester, const HistoryScreen());

      expect(find.text('Aug 2026'), findsOneWidget);
      // Aug 2026 spans 6 grid weeks from Mon Jul 27 to Sun Sep 6.
      final cells = tester.widgetList<CalendarCell>(find.byType(CalendarCell));
      expect(cells.length % 7, 0);
      expect(cells.where((c) => c.day.inMonth).length, 31);
    });

    testWidgets('future days are the future band and are not tappable',
        (tester) async {
      await daily('Running');
      await h.pump(tester, const HistoryScreen());

      final tomorrow = cellFor(tester, 29);
      expect(tomorrow.day.band, DayBand.future);
      expect(tomorrow.onTap, isNull,
          reason: 'a day that has not happened cannot be recorded');

      final laterInMonth = cellFor(tester, 31);
      expect(laterInMonth.day.band, DayBand.future);
    });

    testWidgets('a fully missed past day is weak, a done day is strong',
        (tester) async {
      final id = await daily('Running');
      await h.repo.record(
        commitmentId: id,
        date: d(2026, 8, 26),
        kind: TrackingKind.done,
        nowUtc: h.nowUtc,
        label: 'done',
      );
      await h.pump(tester, const HistoryScreen());

      expect(cellFor(tester, 26).day.band, DayBand.strong);
      expect(cellFor(tester, 25).day.band, DayBand.weak);
    });

    testWidgets('a skipped day is none, never weak', (tester) async {
      final id = await daily('Running');
      await h.repo.record(
        commitmentId: id,
        date: d(2026, 8, 25),
        kind: TrackingKind.skipped,
        nowUtc: h.nowUtc,
        label: 'skip',
      );
      await h.pump(tester, const HistoryScreen());

      expect(
        cellFor(tester, 25).day.band,
        DayBand.none,
        reason: 'choosing not to is not a failure',
      );
    });

    testWidgets('today is pending, so it is not counted as weak',
        (tester) async {
      await daily('Running');
      await h.pump(tester, const HistoryScreen());
      expect(cellFor(tester, 28).day.band, DayBand.none);
    });

    testWidgets('cannot page past the current month', (tester) async {
      await daily('Running');
      await h.pump(tester, const HistoryScreen());

      final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
      );
      expect(next.onPressed, isNull);

      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Jul 2026'), findsOneWidget);
    });

    testWidgets('the month summary reports counts and consistency',
        (tester) async {
      final id = await daily('Running');
      for (final day in [20, 21, 22]) {
        await h.repo.record(
          commitmentId: id,
          date: d(2026, 8, day),
          kind: TrackingKind.done,
          nowUtc: h.nowUtc,
          label: 'done',
        );
      }
      await h.pump(tester, const HistoryScreen());

      // Aug 1-27 elapsed: 3 done, 24 missed. Today (28) is pending.
      // Scoped to the summary card — bare digits also match calendar cells.
      final card = find.byType(Card);
      expect(find.descendant(of: card, matching: find.text('3')),
          findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('24')),
          findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('11%')),
          findsOneWidget);
    });

    testWidgets('a legend explains the bands without relying on colour',
        (tester) async {
      await daily('Running');
      await h.pump(tester, const HistoryScreen());

      // The legend sits below the grid, so the outer list has to be scrolled.
      // Dragging it directly: the nested grid is also a Scrollable, which makes
      // scrollUntilVisible ambiguous.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.text('Strong'), findsOneWidget);
      expect(find.text('Nothing tracked'), findsOneWidget);
      expect(find.text('Not yet'), findsOneWidget);
    });
  });

  group('week grid', () {
    testWidgets('daily rows show seven cells, period rows show one chip',
        (tester) async {
      await daily('Running');
      await h.repo.createCommitment(
        name: 'Gym',
        frequency: const Frequency.timesPerWeek(target: 4),
        startedOn: d(2026, 8, 1),
        nowUtc: h.nowUtc,
      );
      await h.pump(tester, const HistoryScreen());

      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();

      expect(find.text('Aug 24 – Aug 30'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Gym'), findsOneWidget);
      // The weekly commitment is one chip, not seven day cells.
      expect(find.text('0 / 4 this week'), findsOneWidget);
    });

    testWidgets('cannot page past the current week', (tester) async {
      await daily('Running');
      await h.pump(tester, const HistoryScreen());
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();

      final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
      );
      expect(next.onPressed, isNull);
    });
  });
}
