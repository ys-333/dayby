import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/features/commitment/commitment_detail_screen.dart';
import 'package:riyaz/features/commitment/widgets/trend_chart.dart';
import 'package:riyaz/features/commitment/widgets/twelve_week_grid.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/dates.dart';
import '../../support/harness.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late Harness h;
  setUp(() => h = Harness());
  tearDown(() => h.dispose());

  Future<String> seed({
    required CivilDate from,
    List<int> doneOffsets = const [],
  }) async {
    final id = await h.repo.createCommitment(
      name: 'Running',
      frequency: const Frequency.daily(),
      startedOn: from,
      nowUtc: h.nowUtc,
      icon: 'run',
    );
    for (final offset in doneOffsets) {
      await h.repo.record(
        commitmentId: id,
        date: from.plusDays(offset),
        kind: TrackingKind.done,
        nowUtc: h.nowUtc,
        label: 'done',
      );
    }
    return id;
  }


  /// The screen is a long scroll now that the grid is on it, and a `ListView`
  /// only builds what is on screen — so anything below the lead figure has to
  /// be scrolled to before it can be found.
  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.dragUntilVisible(
      target,
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the commitment, its start date and its streaks',
      (tester) async {
    final id = await seed(
      from: d(2026, 8, 1),
      doneOffsets: [0, 1, 2, 3, 4, 8, 9],
    );
    await h.pump(tester, CommitmentDetailScreen(commitmentId: id));

    expect(find.text('Running'), findsWidgets);
    expect(find.text('Since Saturday, Aug 1 2026'), findsOneWidget);
    await scrollTo(tester, find.text('Your best run'));
    expect(find.text('Your best run'), findsOneWidget);
    // Longest run is the first five days.
    expect(find.text('5'), findsWidgets);
  });

  testWidgets('opens with one figure, not a wall of them', (tester) async {
    final id = await seed(
      from: d(2026, 8, 1),
      doneOffsets: [0, 1, 2, 3, 4, 8, 9],
    );
    await h.pump(tester, CommitmentDetailScreen(commitmentId: id));

    // The lead figure states its own denominator. A percentage with no stated
    // base is a number the user can neither argue with nor learn from.
    expect(find.text('this month'), findsOneWidget);
    expect(find.textContaining('scheduled days this month'), findsOneWidget);
  });

  testWidgets('the twelve-week grid is dated, and every cell says its day',
      (tester) async {
    final id = await seed(from: d(2026, 8, 1), doneOffsets: [0, 1, 2]);
    await h.pump(tester, CommitmentDetailScreen(commitmentId: id));

    expect(find.byType(TwelveWeekGrid), findsOneWidget);
    expect(find.text('LAST TWELVE WEEKS'), findsOneWidget);

    final grid = tester.widget<TwelveWeekGrid>(find.byType(TwelveWeekGrid));
    expect(grid.detail.grid, hasLength(84));
    // Anchored to a week start, so each row of the grid is one weekday. A grid
    // anchored to "today minus 83" would put a different weekday in each row
    // and destroy the one pattern it exists to show.
    expect(grid.detail.gridStart.weekday, 1);
    expect(grid.detail.grid.last.date >= h.today, isTrue);
  });

  testWidgets('the grid never draws an unlived day as a failure',
      (tester) async {
    final id = await seed(from: d(2026, 8, 1));
    await h.pump(tester, CommitmentDetailScreen(commitmentId: id));

    final grid = tester.widget<TwelveWeekGrid>(find.byType(TwelveWeekGrid));
    for (final day in grid.detail.grid) {
      if (day.date <= h.today) continue;
      expect(day.isFuture, isTrue);
      expect(day.status, isNot(OccurrenceStatus.missed));
    }
  });

  testWidgets('a period target is not scored day by day in the grid',
      (tester) async {
    final id = await h.repo.createCommitment(
      name: 'Gym',
      frequency: const Frequency.timesPerWeek(target: 4),
      startedOn: d(2026, 8, 1),
      nowUtc: h.nowUtc,
      icon: 'gym',
    );
    await h.repo.record(
      commitmentId: id,
      date: d(2026, 8, 26),
      kind: TrackingKind.done,
      nowUtc: h.nowUtc,
      label: 'done',
    );
    await h.pump(tester, CommitmentDetailScreen(commitmentId: id));

    final grid = tester.widget<TwelveWeekGrid>(find.byType(TwelveWeekGrid));
    expect(grid.detail.isPeriod, isTrue);
    // Where the work landed, marked as its own thing. Never a status: a
    // 4x-a-week target has no opinion about which days it is met on, so
    // painting one "done" would claim that day was owed.
    final credited = grid.detail.grid.where((g) => g.creditedToPeriod);
    expect(credited.map((g) => g.date), contains(d(2026, 8, 26)));
    expect(grid.detail.grid.every((g) => g.status == null), isTrue);
    await scrollTo(tester, find.text('Counted toward a target'));
    expect(find.text('Counted toward a target'), findsOneWidget);
    expect(find.text('Done'), findsNothing);
  });

  testWidgets('the latest note is quoted, and absent when there is none',
      (tester) async {
    final id = await seed(from: d(2026, 8, 1), doneOffsets: [0, 1]);
    await h.pump(tester, CommitmentDetailScreen(commitmentId: id));
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('LATEST NOTE'), findsNothing);

    await h.repo.setNote(
      commitmentId: id,
      date: d(2026, 8, 2),
      note: 'Knee felt off, kept it to twenty minutes.',
    );
    await tester.pumpAndSettle();

    await scrollTo(tester, find.text('LATEST NOTE'));
    expect(find.text('LATEST NOTE'), findsOneWidget);
    expect(
      find.text('Knee felt off, kept it to twenty minutes.'),
      findsOneWidget,
    );
  });

  testWidgets('recovery is an em dash until a lapse has been recovered from',
      (tester) async {
    // Done then still lapsed at the end — no completed gap yet.
    final id = await seed(from: d(2026, 8, 1), doneOffsets: [0, 1, 2]);
    await h.pump(tester, CommitmentDetailScreen(commitmentId: id));

    await scrollTo(tester, find.text('To come back'));
    expect(find.text('To come back'), findsOneWidget);
    expect(
      find.text('—'),
      findsWidgets,
      reason: 'zero would claim a resilience never demonstrated',
    );
  });

  testWidgets('a brand new commitment shows dashes, never zero percent',
      (tester) async {
    final id = await seed(from: d(2026, 8, 28));
    await h.pump(tester, CommitmentDetailScreen(commitmentId: id));

    // Only today exists, and today is pending — nothing is eligible yet.
    await scrollTo(tester, find.text('This week'));
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(find.text('Nothing has settled this month yet'), findsOneWidget,
        reason: 'a month with nothing closed has no consistency, and drawing '
            'that as zero is a verdict on a month still being lived');
  });

  testWidgets('the trend refuses to draw a line with nothing eligible',
      (tester) async {
    // Started today, and today is still pending — zero eligible points, so
    // there is nothing honest to plot.
    final id = await seed(from: d(2026, 8, 28));
    await h.pump(tester, CommitmentDetailScreen(commitmentId: id));

    await scrollTo(tester, find.byType(TrendChart));

    expect(
      find.text('Not enough history for a trend yet.'),
      findsOneWidget,
    );
  });

  testWidgets('a missing commitment fails gracefully', (tester) async {
    await h.pump(
      tester,
      const CommitmentDetailScreen(commitmentId: 'does-not-exist'),
    );
    expect(find.text('This commitment no longer exists.'), findsOneWidget);
  });

  group('geometry', () {
    // The polish suite covers the four tab screens; this one is reached by a
    // push and was never in that list, which is how a twelve-week grid could
    // have shipped overflowing a 320dp phone without a single test noticing.
    for (final (label, size, scale) in [
      ('a small phone', const Size(320, 568), 1.0),
      ('a large text scale', const Size(400, 800), 1.8),
      ('both at once', const Size(320, 568), 1.8),
      ('landscape', const Size(800, 400), 1.0),
    ]) {
      testWidgets('renders and scrolls at $label', (tester) async {
        final id = await seed(
          from: d(2026, 6, 1),
          doneOffsets: [0, 1, 2, 4, 7, 30, 60, 80],
        );
        await h.repo.setNote(
          commitmentId: id,
          date: d(2026, 8, 20),
          note: 'Knee felt off, kept it to twenty minutes and walked home.',
        );

        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: MaterialApp(
              theme: riyazTheme(Brightness.light),
              home: h.scope(CommitmentDetailScreen(commitmentId: id)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'first frame');

        // The grid sizes its cells to the width it is given, so an overflow
        // would only appear once it is on screen — scroll the whole thing.
        for (var i = 0; i < 8; i++) {
          await tester.drag(find.byType(ListView), const Offset(0, -300));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'after scroll $i');
        }
      });
    }
  });
}
