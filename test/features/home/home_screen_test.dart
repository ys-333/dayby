import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/data/db/app_database.dart';
import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/domain/time/clock.dart';
import 'package:riyaz/features/home/home_screen.dart';
import 'package:riyaz/features/home/widgets/commitment_tile.dart';
import 'package:riyaz/app/theme/palette.dart';
import 'package:riyaz/app/theme/tokens.dart';
import 'package:riyaz/features/home/today_controller.dart';
import 'package:riyaz/features/home/widgets/period_tile.dart';
import 'package:riyaz/features/home/widgets/recent_strip.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/dates.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late TrackingRepository repo;

  // Friday 2026-08-28, 10:00 IST.
  final clock = FixedClock.iso('2026-08-28T10:00:00+05:30');
  final nowUtc = clock.nowUtc();

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TrackingRepository(db);
  });
  tearDown(() => db.close());

  Future<void> addCommitment({
    required String name,
    Frequency frequency = const Frequency.daily(),
    String icon = '🏃',
    CivilDate? startedOn,
  }) =>
      repo.createCommitment(
        name: name,
        frequency: frequency,
        startedOn: startedOn ?? d(2026, 8, 1),
        nowUtc: nowUtc,
        icon: icon,
      );

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(clock),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The row's resolved status, read off the model the tile was handed.
  ///
  /// The redesign removed the "Done" / "Not done yet" caption from a daily
  /// row — an open ring and a filled tick already say it, and a column of
  /// captions under every untouched commitment was the noise the device pass
  /// objected to. So these tests assert the state, not a string that is
  /// deliberately no longer on screen.
  OccurrenceStatus statusOf(WidgetTester tester, String name) => tester
      .widgetList<CommitmentTile>(find.byType(CommitmentTile))
      .firstWhere((t) => t.item.commitment.name == name)
      .item
      .status;

  group('rendering', () {
    testWidgets('an empty database shows the empty state', (tester) async {
      await pumpHome(tester);
      expect(find.text('Nothing to track yet.'), findsOneWidget);
    });

    testWidgets('a daily commitment appears as pending', (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      expect(find.text('Running'), findsOneWidget);
      expect(statusOf(tester, 'Running'), OccurrenceStatus.pending);
      expect(find.text('Not done yet'), findsNothing,
          reason: 'the open ring says it; the caption was noise');
    });

    testWidgets('a daily commitment sits under the Today group',
        (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('0 OF 1'), findsOneWidget);
    });

    testWidgets('a weekly target reads as a period, not a day', (tester) async {
      await addCommitment(
        name: 'Gym',
        frequency: const Frequency.timesPerWeek(target: 4),
        icon: '🏋️',
      );
      await pumpHome(tester);

      expect(find.byType(PeriodTile), findsOneWidget);
      expect(find.byType(CommitmentTile), findsNothing);
      expect(find.text('0 of 4'), findsOneWidget);
    });

    testWidgets('period targets never share a group with daily rows',
        (tester) async {
      await addCommitment(name: 'Running');
      await addCommitment(
        name: 'Gym',
        frequency: const Frequency.timesPerWeek(target: 4),
      );
      await pumpHome(tester);

      // Principle 3: a 3x-a-week target cannot be late on a Tuesday, so it
      // must not sit in a list of things that can.
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('THIS WEEK'), findsOneWidget);
      expect(find.text('NEVER LATE'), findsOneWidget);
    });

    testWidgets('a monthly target names its own period', (tester) async {
      await addCommitment(
        name: 'Deep clean',
        frequency: const Frequency.timesPerMonth(target: 2),
      );
      await pumpHome(tester);

      expect(find.text('THIS MONTH'), findsOneWidget);
    });

    testWidgets('the day bar shows today and disables tomorrow',
        (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      expect(find.text('Today'), findsOneWidget);

      final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
      );
      expect(next.onPressed, isNull, reason: 'the future cannot be recorded');
    });

    testWidgets('add lives in the day bar, not over the last row',
        (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      expect(find.byType(FloatingActionButton), findsNothing,
          reason: 'the FAB covered the last row on device');
      expect(
        find.widgetWithIcon(IconButton, Icons.add_rounded),
        findsOneWidget,
      );
    });
  });

  group('the recent-days strip', () {
    testWidgets('draws cells with real height, not a hairline', (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      final cells = find.descendant(
        of: find.byType(RecentStrip),
        matching: find.byType(DecoratedBox),
      );
      expect(cells, findsNWidgets(recentStripLength));

      // The bug this pins: a cell is a childless `DecoratedBox`, so under a
      // Row's default `center` alignment it sizes to the child it does not
      // have and collapses to zero height. The SizedBox still reserves its
      // 24dp, nothing throws, and every "does it render" test passes — the
      // whole strip just becomes one faint dash. Only measuring catches it.
      for (var i = 0; i < recentStripLength; i++) {
        final size = tester.getSize(cells.at(i));
        expect(size.height, Sizes.stripCell,
            reason: 'cell $i collapsed to ${size.height}dp');
        expect(size.width, greaterThan(0));
      }
    });

    testWidgets('every settled day is a fill on the ramp, never a ring',
        (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      final palette = Palette.of(Brightness.light);
      final cells = find.descendant(
        of: find.byType(RecentStrip),
        matching: find.byType(DecoratedBox),
      );

      for (var i = 0; i < recentStripLength; i++) {
        final box = tester.widget<DecoratedBox>(cells.at(i));
        final decoration = box.decoration as BoxDecoration;

        // The strip is a density ramp, not a status readout. A clay ring here
        // read as an alarm on a device — see `_Cell`'s doc — and no cell may
        // carry one again. The only border allowed is today's marker.
        expect(decoration.color, isNotNull, reason: 'cell $i has no fill');
        expect(palette.heat, contains(decoration.color),
            reason: 'cell $i is off the heat ramp');
        expect(decoration.border == null || i == recentStripLength - 1, isTrue,
            reason: 'cell $i has a ring, and only today may');
        expect(decoration.color, isNot(palette.clay));
      }
    });

    testWidgets('marks the day being shown, and only that day', (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      final strip = tester.widget<RecentStrip>(find.byType(RecentStrip));
      expect(strip.days, hasLength(recentStripLength));
      expect(strip.days.where((d) => d.isAnchor), hasLength(1));
      expect(strip.days.last.isAnchor, isTrue);
      expect(strip.caption, 'Today still open');
    });
  });

  group('the headline counts down', () {
    testWidgets('an untouched day names what is left, never a score',
        (tester) async {
      await addCommitment(name: 'Running');
      await addCommitment(name: 'Reading', icon: '📚');
      await pumpHome(tester);

      expect(find.text('Two left today'), findsOneWidget);
      expect(find.text('0%'), findsNothing,
          reason: 'a percentage of a day still being lived is a verdict');
    });

    testWidgets('finishing everything reaches zero', (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      await tester.tap(find.text('Running'));
      await tester.pumpAndSettle();

      expect(find.text('Done for today'), findsOneWidget);
    });

    testWidgets('a period target is never part of what is left today',
        (tester) async {
      await addCommitment(
        name: 'Gym',
        frequency: const Frequency.timesPerWeek(target: 4),
      );
      await pumpHome(tester);

      expect(find.text('Nothing due today'), findsOneWidget);
    });

    testWidgets('a skipped row is not something left to do', (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);
      expect(find.text('One left today'), findsOneWidget);

      await tester.longPress(find.text('Running'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing due today'), findsOneWidget);
    });

    testWidgets('a closed day tallies instead of counting down',
        (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();

      // The no-scoring rule protects a day the user can still act on. Once it
      // is over, the count is a fact rather than a judgement delivered early.
      expect(find.text('0 of 1 done'), findsOneWidget);
    });
  });

  group('one-tap tracking', () {
    testWidgets('tapping a row marks it done and updates the headline',
        (tester) async {
      await addCommitment(name: 'Running');
      await addCommitment(name: 'Reading', icon: '📚');
      await pumpHome(tester);

      await tester.tap(find.text('Running'));
      await tester.pumpAndSettle();

      expect(statusOf(tester, 'Running'), OccurrenceStatus.done);
      expect(find.text('One left today'), findsOneWidget);
      expect(find.text('1 OF 2'), findsOneWidget);
    });

    testWidgets('every tap offers an undo', (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      await tester.tap(find.text('Running'));
      await tester.pumpAndSettle();

      expect(find.text('Running marked done'), findsOneWidget);
      expect(find.text('UNDO'), findsOneWidget);
    });

    testWidgets('undo restores the previous state', (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      await tester.tap(find.text('Running'));
      await tester.pumpAndSettle();
      expect(statusOf(tester, 'Running'), OccurrenceStatus.done);

      await tester.tap(find.text('UNDO'));
      await tester.pumpAndSettle();

      expect(statusOf(tester, 'Running'), OccurrenceStatus.pending);
      expect(find.text('One left today'), findsOneWidget);
    });

    testWidgets('tapping a finished row un-ticks it', (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      await tester.tap(find.text('Running'));
      await tester.pumpAndSettle();
      expect(statusOf(tester, 'Running'), OccurrenceStatus.done);

      await tester.tap(find.text('Running'));
      await tester.pumpAndSettle();
      expect(statusOf(tester, 'Running'), OccurrenceStatus.pending);
    });

    testWidgets('a period row increments instead of completing',
        (tester) async {
      await addCommitment(
        name: 'Gym',
        frequency: const Frequency.timesPerWeek(target: 4),
      );
      await pumpHome(tester);

      await tester.tap(find.text('Gym'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 4'), findsOneWidget);

      await tester.tap(find.text('Gym'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 4'), findsOneWidget);
    });

    testWidgets('an open period behind target never reads as missed',
        (tester) async {
      await addCommitment(
        name: 'Gym',
        frequency: const Frequency.timesPerWeek(target: 4),
      );
      await pumpHome(tester);

      await tester.tap(find.text('Gym'));
      await tester.pumpAndSettle();

      expect(find.text('Missed'), findsNothing);
      expect(find.text('1 of 4'), findsOneWidget);
    });

    testWidgets('a met target is said out loud rather than just disappearing',
        (tester) async {
      await addCommitment(
        name: 'Gym',
        frequency: const Frequency.timesPerWeek(target: 2),
      );
      await pumpHome(tester);

      await tester.tap(find.text('Gym'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gym'));
      await tester.pumpAndSettle();

      expect(find.text('Gym is done for the week'), findsOneWidget);
    });
  });

  group('long press actions', () {
    testWidgets('offers partial, skip and clear', (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      await tester.longPress(find.text('Running'));
      await tester.pumpAndSettle();

      expect(find.text('Mark partial'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      expect(
        find.text("Won't count against consistency"),
        findsOneWidget,
        reason: 'the skip/miss distinction must be visible at the point of use',
      );
    });

    testWidgets('skipping leaves the group tally, and stays visible',
        (tester) async {
      await addCommitment(name: 'Running');
      await addCommitment(name: 'Reading', icon: '📚');
      await pumpHome(tester);

      expect(find.text('0 OF 2'), findsOneWidget);

      await tester.longPress(find.text('Running'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      // Skipped rows leave the denominator, exactly as they leave consistency
      // — but principle 6 says they are shown, never hidden.
      expect(find.text('0 OF 1'), findsOneWidget);
      expect(find.text('Skipped'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
    });

    testWidgets('marking partial shows partial, not done', (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      await tester.longPress(find.text('Running'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark partial'));
      await tester.pumpAndSettle();

      expect(find.text('Running marked partial'), findsOneWidget);
      // The row still reads pending, and that is the engine being right rather
      // than the screen being wrong: an open window is PENDING, and a partial
      // recorded at ten in the morning must not close a day the user can still
      // finish. The caption appears once the day is over.
      expect(statusOf(tester, 'Running'), OccurrenceStatus.pending);
    });

    testWidgets('a partial on a closed day is captioned as one',
        (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Running'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark partial'));
      await tester.pumpAndSettle();

      expect(statusOf(tester, 'Running'), OccurrenceStatus.partial);
      expect(find.text('Partial'), findsOneWidget);
    });
  });

  group('backfill', () {
    testWidgets('stepping back opens a previous day for recording',
        (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Thursday, Aug 27'), findsOneWidget);
      // A closed day with nothing recorded reads as missed, not pending.
      expect(find.text('Missed'), findsOneWidget);
    });

    testWidgets('recording on a past day sticks and does not touch today',
        (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Running'));
      await tester.pumpAndSettle();
      expect(statusOf(tester, 'Running'), OccurrenceStatus.done);

      // Back to today: still untouched.
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
      expect(statusOf(tester, 'Running'), OccurrenceStatus.pending);
    });
  });

  group('notes', () {
    testWidgets('a note is offered only once something is recorded',
        (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      await tester.longPress(find.text('Running'));
      await tester.pumpAndSettle();
      expect(find.text('Add note'), findsNothing,
          reason: 'a note has no event to attach to yet');
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Running'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Running'));
      await tester.pumpAndSettle();
      expect(find.text('Add note'), findsOneWidget);
    });

    testWidgets('a saved note survives and shows on the row', (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      await tester.tap(find.text('Running'));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Running'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add note'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Ran 5k in the rain');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // The note is the row's second line now, not a thing you have to reopen
      // a dialog to see.
      expect(
        find.descendant(
          of: find.byType(CommitmentTile),
          matching: find.text('Ran 5k in the rain'),
        ),
        findsOneWidget,
      );

      // Reopen: still prefilled, so it round-tripped through storage.
      await tester.longPress(find.text('Running'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add note'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Ran 5k in the rain',
      );
    });
  });
}
