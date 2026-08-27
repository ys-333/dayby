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
import 'package:riyaz/features/add_commitment/add_commitment_screen.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/dates.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late TrackingRepository repo;
  final clock = FixedClock.iso('2026-08-28T10:00:00+05:30');
  final range = CivilDateRange(d(2026, 8, 1), d(2026, 9, 30));

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TrackingRepository(db);
  });
  tearDown(() => db.close());

  Future<void> pumpAdd(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(clock),
        ],
        child: const MaterialApp(home: AddCommitmentScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('create is disabled until there is a name', (tester) async {
    await pumpAdd(tester);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create'),
    );
    expect(button.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Running');
    await tester.pumpAndSettle();

    final enabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create'),
    );
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('a template fills the form in one tap', (tester) async {
    await pumpAdd(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'Gym'));
    await tester.pumpAndSettle();

    // Gym is a 4x/week template, so the frequency follows the template too.
    expect(find.text('4x per week'), findsOneWidget);
  });

  testWidgets('creating persists the commitment with its schedule',
      (tester) async {
    await pumpAdd(tester);
    await tester.enterText(find.byType(TextField), 'Running');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    final snapshot = await repo.read(range);
    expect(snapshot.commitments, hasLength(1));
    expect(snapshot.commitments.single.name, 'Running');
    expect(snapshot.commitments.single.startedOn, d(2026, 8, 28));
    expect(
      snapshot.schedulesFor(snapshot.commitments.single.id).single.frequency,
      const Frequency.daily(),
    );
  });

  testWidgets('a template creates with the template frequency',
      (tester) async {
    await pumpAdd(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'Gym'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    final snapshot = await repo.read(range);
    expect(
      snapshot.schedulesFor(snapshot.commitments.single.id).single.frequency,
      const Frequency.timesPerWeek(target: 4),
    );
  });

  testWidgets('advanced options change the frequency', (tester) async {
    await pumpAdd(tester);
    await tester.enterText(find.byType(TextField), 'Books');
    await tester.tap(find.text('Frequency'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Per month'));
    await tester.pumpAndSettle();
    expect(find.text('4x per month'), findsOneWidget);
  });

  group('active commitment soft cap', () {
    Future<void> seedDaily(int n) async {
      for (var i = 0; i < n; i++) {
        await repo.createCommitment(
          name: 'Daily $i',
          frequency: const Frequency.daily(),
          startedOn: d(2026, 8, 1),
          nowUtc: clock.nowUtc(),
        );
      }
    }

    testWidgets('warns past six daily commitments but does not block',
        (tester) async {
      await seedDaily(6);
      await pumpAdd(tester);
      await tester.enterText(find.byType(TextField), 'One more');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.text('That is a lot to hold'), findsOneWidget);

      await tester.tap(find.text('Add anyway'));
      await tester.pumpAndSettle();

      final snapshot = await repo.read(range);
      expect(snapshot.commitments, hasLength(7),
          reason: 'the cap is advisory, never a block');
    });

    testWidgets('cancelling the warning creates nothing', (tester) async {
      await seedDaily(6);
      await pumpAdd(tester);
      await tester.enterText(find.byType(TextField), 'One more');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect((await repo.read(range)).commitments, hasLength(6));
    });

    testWidgets('period commitments do not trigger the daily cap',
        (tester) async {
      await seedDaily(6);
      await pumpAdd(tester);
      await tester.tap(find.widgetWithText(ActionChip, 'Gym'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.text('That is a lot to hold'), findsNothing);
      expect((await repo.read(range)).commitments, hasLength(7));
    });
  });
}
