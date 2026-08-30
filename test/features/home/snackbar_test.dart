import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/features/home/widgets/commitment_tile.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/data/db/app_database.dart';
import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/time/clock.dart';
import 'package:riyaz/features/home/home_screen.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/dates.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late TrackingRepository repo;
  final clock = FixedClock.iso('2026-08-28T10:00:00+05:30');

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TrackingRepository(db);
  });
  tearDown(() => db.close());

  Future<void> pumpHome(WidgetTester tester) async {
    await repo.createCommitment(
      name: 'Running',
      frequency: const Frequency.daily(),
      startedOn: d(2026, 8, 1),
      nowUtc: clock.nowUtc(),
      icon: '🏃',
    );
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

  testWidgets('the undo bar goes away on its own', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('Running'));
    await tester.pumpAndSettle();
    expect(find.text('UNDO'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('UNDO'), findsNothing,
        reason: 'the undo bar must not sit over the screen forever');
  });

  testWidgets('undo still works inside the window', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('Running'));
    await tester.pumpAndSettle();
    expect(_status(tester), OccurrenceStatus.done);

    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();
    expect(_status(tester), OccurrenceStatus.pending);
  });

  testWidgets('a second action does not leave the first bar stranded',
      (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('Running'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Running'));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('UNDO'), findsNothing);
  });
}

/// The single row's resolved status. A daily row no longer captions itself —
/// see `home_screen_test.dart` — so the state is read off the model.
OccurrenceStatus _status(WidgetTester tester) =>
    tester.widget<CommitmentTile>(find.byType(CommitmentTile)).item.status;
