import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/features/commitment/commitment_detail_screen.dart';
import 'package:riyaz/features/commitment/widgets/trend_chart.dart';
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
      icon: '🏃',
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

  testWidgets('shows the commitment, its start date and its streaks',
      (tester) async {
    final id = await seed(
      from: d(2026, 8, 1),
      doneOffsets: [0, 1, 2, 3, 4, 8, 9],
    );
    await h.pump(tester, CommitmentDetailScreen(commitmentId: id));

    expect(find.text('Running'), findsWidgets);
    expect(find.text('Started Aug 1, 2026'), findsOneWidget);
    expect(find.text('Current streak'), findsOneWidget);
    // Longest run is the first five days.
    expect(find.text('5'), findsWidgets);
  });

  testWidgets('recovery is an em dash until a lapse has been recovered from',
      (tester) async {
    // Done then still lapsed at the end — no completed gap yet.
    final id = await seed(from: d(2026, 8, 1), doneOffsets: [0, 1, 2]);
    await h.pump(tester, CommitmentDetailScreen(commitmentId: id));

    expect(find.text('Avg recovery'), findsOneWidget);
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
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('the trend refuses to draw a line with nothing eligible',
      (tester) async {
    // Started today, and today is still pending — zero eligible points, so
    // there is nothing honest to plot.
    final id = await seed(from: d(2026, 8, 28));
    await h.pump(tester, CommitmentDetailScreen(commitmentId: id));

    await tester.dragUntilVisible(
      find.byType(TrendChart),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

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
}
