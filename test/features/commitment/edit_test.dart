import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/time/accounting_calendar.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/features/commitment/commitment_detail_screen.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/dates.dart';
import '../../support/harness.dart';

/// Editing a commitment must not edit its past.
///
/// The schedule is the source of truth for what was expected, so an in-place
/// rewrite of the current schedule row would retroactively change what every
/// past day was measured against — a year-old daily habit switched to 3×/week
/// would re-resolve twelve months against a target nobody was ever held to.
/// Nothing throws when that happens; the numbers simply become wrong.
///
/// So these resolve *across* the change date in both directions. Asserting
/// only forward is the mistake that let the archive bug ship.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  late Harness h;
  setUp(() => h = Harness(at: '2026-08-28T10:00:00+05:30'));
  tearDown(() => h.dispose());

  Future<String> dailySince(CivilDate from) => h.repo.createCommitment(
        name: 'Running',
        frequency: const Frequency.daily(),
        startedOn: from,
        nowUtc: h.nowUtc,
      );

  group('renaming', () {
    test('touches no schedule and no number', () async {
      final id = await dailySince(d(2026, 8, 1));
      final range = CivilDateRange(d(2026, 8, 1), d(2026, 8, 27));
      final before = await h.resolutionFor(range, id);

      await h.repo.updateCommitment(
        commitmentId: id,
        on: h.today,
        name: 'Morning run',
        icon: '🏃',
      );

      final snap = await h.repo.readAll();
      expect(snap.commitments.single.name, 'Morning run');
      expect(snap.schedulesFor(id), hasLength(1),
          reason: 'a rename must not version the schedule');

      final after = await h.resolutionFor(range, id);
      expect(after.length, before.length);
      for (var i = 0; i < before.length; i++) {
        expect(after[i].status, before[i].status);
      }
    });
  });

  group('changing frequency', () {
    test('opens a new version and closes the old one the day before',
        () async {
      final id = await dailySince(d(2026, 8, 1));
      await h.repo.updateCommitment(
        commitmentId: id,
        on: d(2026, 8, 15),
        frequency: const Frequency.timesPerWeek(target: 3),
      );

      final schedules = (await h.repo.readAll()).schedulesFor(id)
        ..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
      expect(schedules, hasLength(2));
      expect(schedules.first.effectiveFrom, d(2026, 8, 1));
      expect(schedules.first.effectiveTo, d(2026, 8, 14),
          reason: 'the old rules end the day before the new ones begin — '
              'no gap, no overlap');
      expect(schedules.last.effectiveFrom, d(2026, 8, 15));
      expect(schedules.last.effectiveTo, isNull);
    });

    test('the past is still judged by the rules it was lived under', () async {
      final id = await dailySince(d(2026, 8, 1));
      // Done on four of the first fourteen days.
      for (final day in [2, 5, 9, 13]) {
        await h.repo.record(
          commitmentId: id,
          date: d(2026, 8, day),
          kind: TrackingKind.done,
          nowUtc: h.nowUtc,
          label: 'done',
        );
      }

      final past = CivilDateRange(d(2026, 8, 1), d(2026, 8, 14));
      final before = await h.resolutionFor(past, id);
      expect(before, hasLength(14), reason: 'daily: one occurrence a day');

      await h.repo.updateCommitment(
        commitmentId: id,
        on: d(2026, 8, 15),
        frequency: const Frequency.timesPerWeek(target: 3),
      );

      final after = await h.resolutionFor(past, id);
      expect(after, hasLength(14),
          reason: 'the past was daily and must stay daily — collapsing it into '
              'weekly periods rewrites what was expected');
      for (var i = 0; i < before.length; i++) {
        expect(after[i].status, before[i].status,
            reason: 'status on ${before[i].occurrence.span.start.iso} moved');
        expect(after[i].credit, before[i].credit);
      }
    });

    test('the future is judged by the new rules', () async {
      final id = await dailySince(d(2026, 8, 1));
      await h.repo.updateCommitment(
        commitmentId: id,
        on: d(2026, 8, 15),
        frequency: const Frequency.timesPerWeek(target: 3),
      );

      final after = await h.resolutionFor(
        CivilDateRange(d(2026, 8, 17), d(2026, 8, 23)),
        id,
      );
      // One weekly period, not seven daily occurrences.
      expect(after, hasLength(1));
      expect(after.single.target, 3);
      expect(after.single.occurrence.scope, PeriodScope.weekly);
    });

    test('editing twice in a day amends instead of leaving an empty version',
        () async {
      final id = await dailySince(d(2026, 8, 1));
      await h.repo.updateCommitment(
        commitmentId: id,
        on: d(2026, 8, 15),
        frequency: const Frequency.timesPerWeek(target: 3),
      );
      await h.repo.updateCommitment(
        commitmentId: id,
        on: d(2026, 8, 15),
        frequency: const Frequency.timesPerWeek(target: 5),
      );

      final schedules = (await h.repo.readAll()).schedulesFor(id);
      expect(schedules, hasLength(2),
          reason: 'a second edit the same day must not create a version whose '
              'end precedes its start');
      for (final s in schedules) {
        if (s.effectiveTo != null) {
          expect(s.effectiveFrom <= s.effectiveTo!, isTrue,
              reason: 'empty schedule version: '
                  '${s.effectiveFrom.iso} to ${s.effectiveTo!.iso}');
        }
      }
    });

    test('a commitment created today amends its only version', () async {
      final id = await dailySince(h.today);
      await h.repo.updateCommitment(
        commitmentId: id,
        on: h.today,
        frequency: const Frequency.timesPerWeek(target: 4),
      );

      final schedules = (await h.repo.readAll()).schedulesFor(id);
      expect(schedules, hasLength(1));
      expect(schedules.single.effectiveTo, isNull);
      expect(schedules.single.frequency,
          const Frequency.timesPerWeek(target: 4));
    });

    test('an archived commitment keeps its closed schedule', () async {
      final id = await dailySince(d(2026, 8, 1));
      await h.repo.archiveCommitment(id, d(2026, 8, 10));
      await h.repo.updateCommitment(
        commitmentId: id,
        on: h.today,
        frequency: const Frequency.timesPerWeek(target: 3),
      );

      final schedules = (await h.repo.readAll()).schedulesFor(id);
      expect(schedules, hasLength(1),
          reason: 'reopening a schedule through the back door would restart '
              'the miss-a-day bleed archiving exists to stop');
      expect(schedules.single.effectiveTo, d(2026, 8, 10));

      final after = await h.resolutionFor(
        CivilDateRange(d(2026, 8, 11), d(2026, 8, 27)),
        id,
      );
      expect(after.where((r) => r.status == OccurrenceStatus.missed), isEmpty);
    });
  });

  group('the sheet', () {
    testWidgets('renames from the menu and says history is unchanged',
        (tester) async {
      final id = await dailySince(d(2026, 8, 1));
      await h.pump(tester, CommitmentDetailScreen(commitmentId: id));

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Running'), 'Morning run');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        (await h.repo.readAll()).commitments.single.name,
        'Morning run',
      );
      // A rename is not a schedule change, so it must not claim to be one.
      expect(find.text('Saved.'), findsOneWidget);
    });

    testWidgets('a frequency change is announced as leaving history alone',
        (tester) async {
      final id = await dailySince(d(2026, 8, 1));
      await h.pump(tester, CommitmentDetailScreen(commitmentId: id));

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Per week'));
      await tester.pumpAndSettle();
      expect(find.textContaining('your history does not change'),
          findsOneWidget,
          reason: 'the user has to be told before they commit to it, not '
              'left to assume their past just moved');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final schedules = (await h.repo.readAll()).schedulesFor(id);
      expect(schedules, hasLength(2));
      expect(find.textContaining('history is unchanged'), findsOneWidget);
    });
  });
}
