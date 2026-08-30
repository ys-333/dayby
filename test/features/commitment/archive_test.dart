import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/features/commitment/commitment_detail_screen.dart';
import 'package:riyaz/features/home/home_screen.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/dates.dart';
import '../../support/harness.dart';

/// Archiving is the one action that looks destructive and must not be.
///
/// The product rule is that history is preserved — never rewritten, never
/// deleted — so the numbers on every screen that reports the past have to be
/// unchanged by it. That is asserted here directly rather than trusted,
/// because the failure mode is silent: nothing throws when a year of history
/// quietly stops counting.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  late Harness h;
  setUp(() => h = Harness());
  tearDown(() => h.dispose());

  Future<String> seedWithHistory(String name) async {
    final id = await h.repo.createCommitment(
      name: name,
      frequency: const Frequency.daily(),
      startedOn: d(2026, 8, 1),
      nowUtc: h.nowUtc,
    );
    // A fortnight of real behaviour: some done, one missed by omission.
    for (final day in [1, 2, 3, 5, 6, 8, 9, 10, 12, 15, 20, 25]) {
      await h.repo.record(
        commitmentId: id,
        date: d(2026, 8, day),
        kind: TrackingKind.done,
        nowUtc: h.nowUtc,
        label: 'done',
      );
    }
    return id;
  }

  test('archiving changes no historical number', () async {
    final id = await seedWithHistory('Running');
    final range = CivilDateRange(d(2026, 8, 1), d(2026, 8, 28));

    final before = await h.resolutionFor(range, id);
    await h.actions().archive(id);
    final after = await h.resolutionFor(range, id);

    expect(after.length, before.length,
        reason: 'archiving must not remove occurrences from history');
    for (var i = 0; i < before.length; i++) {
      expect(after[i].status, before[i].status,
          reason: 'status on ${before[i].occurrence.span.start.iso} changed');
      expect(after[i].credit, before[i].credit);
    }
  });

  test('nothing is expected after the archive date', () async {
    // The test that was missing. The original pair resolved only up to the
    // archive date — the one window in which "archiving changes nothing"
    // happens to be true. Seven weeks later it is not: a commitment whose
    // schedule stays open keeps generating expected occurrences, and every one
    // of them turns MISSED as its day closes. Measured at 49 of 49 before the
    // fix, with archiving making no difference whatsoever.
    final h2 = Harness(at: '2026-09-29T10:00:00+05:30');
    addTearDown(h2.dispose);
    final id = await h2.repo.createCommitment(
      name: 'Running',
      frequency: const Frequency.daily(),
      startedOn: d(2026, 8, 1),
      nowUtc: h2.nowUtc,
    );
    await h2.repo.archiveCommitment(id, d(2026, 8, 10));

    final after = await h2.resolutionFor(
      CivilDateRange(d(2026, 8, 11), d(2026, 9, 28)),
      id,
    );
    expect(
      after.where((r) => r.status == OccurrenceStatus.missed),
      isEmpty,
      reason: 'an archived commitment may never accrue another miss',
    );
  });

  test('history before the archive date is still scored', () async {
    // The other half: closing the schedule must not reach backwards.
    final h2 = Harness(at: '2026-09-29T10:00:00+05:30');
    addTearDown(h2.dispose);
    final id = await h2.repo.createCommitment(
      name: 'Running',
      frequency: const Frequency.daily(),
      startedOn: d(2026, 8, 1),
      nowUtc: h2.nowUtc,
    );
    await h2.repo.record(
      commitmentId: id,
      date: d(2026, 8, 5),
      kind: TrackingKind.done,
      nowUtc: h2.nowUtc,
      label: 'done',
    );
    await h2.repo.archiveCommitment(id, d(2026, 8, 10));

    final before = await h2.resolutionFor(
      CivilDateRange(d(2026, 8, 1), d(2026, 8, 10)),
      id,
    );
    expect(before, hasLength(10), reason: 'the past stays expected');
    expect(
      before.where((r) => r.status == OccurrenceStatus.done),
      hasLength(1),
    );
  });

  test('archiving records the day and keeps every event', () async {
    final id = await seedWithHistory('Running');
    final eventsBefore = (await h.repo.readAll()).events.length;

    await h.actions().archive(id);

    final snapshot = await h.repo.readAll();
    final commitment = snapshot.commitments.firstWhere((c) => c.id == id);
    expect(commitment.state, CommitmentState.archived);
    expect(commitment.archivedOn, d(2026, 8, 28));
    expect(snapshot.events.length, eventsBefore,
        reason: 'no event may be deleted or rewritten');
  });

  test('unarchiving clears the archived day in the same write', () async {
    final id = await seedWithHistory('Running');
    await h.actions().archive(id);
    await h.actions().unarchive(id);

    final commitment =
        (await h.repo.readAll()).commitments.firstWhere((c) => c.id == id);
    expect(commitment.state, CommitmentState.active);
    expect(commitment.archivedOn, isNull,
        reason: 'a live commitment carrying an archived date is a lie the '
            'next screen to read it will repeat');
  });

  testWidgets('an archived commitment leaves the daily list', (tester) async {
    final id = await seedWithHistory('Running');
    await h.pump(tester, const HomeScreen());
    expect(find.text('Running'), findsOneWidget);

    await h.actions().archive(id);
    await tester.pumpAndSettle();

    expect(find.text('Running'), findsNothing);
  });

  testWidgets('the menu archives, says history is kept, and undoes',
      (tester) async {
    final id = await seedWithHistory('Running');
    await h.pump(tester, CommitmentDetailScreen(commitmentId: id));

    // By the icon rather than the type: the menu is keyed on a private enum,
    // so its generic cannot be named from here — and this is what a finger
    // actually lands on.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Archive'), findsOneWidget);

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    // The word "archived" reads as "deleted" to most people, so the screen has
    // to say otherwise in the same breath.
    expect(find.textContaining('history is kept'), findsWidgets);
    expect(
      (await h.repo.readAll()).commitments.firstWhere((c) => c.id == id).state,
      CommitmentState.archived,
    );

    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();
    expect(
      (await h.repo.readAll()).commitments.firstWhere((c) => c.id == id).state,
      CommitmentState.active,
    );
  });
}
