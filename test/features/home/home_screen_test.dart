import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/data/db/app_database.dart';
import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/domain/time/clock.dart';
import 'package:riyaz/features/home/home_screen.dart';
import 'package:riyaz/features/home/widgets/commitment_tile.dart';
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

  group('rendering', () {
    testWidgets('an empty database shows the empty state', (tester) async {
      await pumpHome(tester);
      expect(find.text('Nothing to track yet.'), findsOneWidget);
    });

    testWidgets('a daily commitment appears as pending', (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Not done yet'), findsOneWidget);
      expect(find.text('0 / 1'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
    });

    testWidgets('a weekly target reads as a period, not a day', (tester) async {
      await addCommitment(
        name: 'Gym',
        frequency: const Frequency.timesPerWeek(target: 4),
        icon: '🏋️',
      );
      await pumpHome(tester);

      expect(find.text('0 / 4 this week'), findsOneWidget);
      // A period row offers "+" because a tap adds one rather than finishing.
      // Scoped to the tile: the add FAB shares the icon.
      expect(
        find.descendant(
          of: find.byType(CommitmentTile),
          matching: find.byIcon(Icons.add_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the header shows today and disables tomorrow', (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Friday, Aug 28'), findsOneWidget);

      final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
      );
      expect(next.onPressed, isNull, reason: 'the future cannot be recorded');
    });
  });

  group('one-tap tracking', () {
    testWidgets('tapping a row marks it done and updates progress',
        (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      await tester.tap(find.text('Running'));
      await tester.pumpAndSettle();

      expect(find.text('Done'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('1 / 1'), findsOneWidget);
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
      expect(find.text('Done'), findsOneWidget);

      await tester.tap(find.text('UNDO'));
      await tester.pumpAndSettle();

      expect(find.text('Not done yet'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
    });

    testWidgets('tapping a finished row un-ticks it', (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      await tester.tap(find.text('Running'));
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsOneWidget);

      await tester.tap(find.text('Running'));
      await tester.pumpAndSettle();
      expect(find.text('Not done yet'), findsOneWidget);
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
      expect(find.text('1 / 4 this week'), findsOneWidget);

      await tester.tap(find.text('Gym'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 4 this week'), findsOneWidget);
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
      expect(find.text('1 / 4 this week'), findsOneWidget);
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

    testWidgets('skipping removes the row from the progress denominator',
        (tester) async {
      await addCommitment(name: 'Running');
      await addCommitment(name: 'Reading', icon: '📚');
      await pumpHome(tester);

      // Two rows, nothing done.
      expect(find.text('0 / 2'), findsOneWidget);

      await tester.longPress(find.text('Running'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      // Skipped rows leave the denominator, exactly as they leave consistency.
      expect(find.text('0 / 1'), findsOneWidget);
      expect(find.text('Skipped'), findsOneWidget);
    });

    testWidgets('marking partial shows partial, not done', (tester) async {
      await addCommitment(name: 'Running');
      await pumpHome(tester);

      await tester.longPress(find.text('Running'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark partial'));
      await tester.pumpAndSettle();

      expect(find.text('Running marked partial'), findsOneWidget);
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
      expect(find.text('Done'), findsOneWidget);

      // Back to today: still untouched.
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Not done yet'), findsOneWidget);
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

    testWidgets('a saved note survives and reopens for editing',
        (tester) async {
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

      // Reopen: the note is prefilled, so it round-tripped through storage.
      await tester.longPress(find.text('Running'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add note'));
      await tester.pumpAndSettle();
      expect(find.text('Ran 5k in the rain'), findsOneWidget);
    });
  });
}
