import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/data/backup/backup_codec.dart';
import 'package:riyaz/data/backup/backup_document.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/pause_period.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/features/commitment/commitment_detail_screen.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/dates.dart';
import '../../support/harness.dart';

/// Pause is the action with the largest gap between "looks right" and "is
/// right".
///
/// `CommitmentState.paused` exists on the model and has never had a single
/// reader: `lib/domain/` consults `PausePeriods` and nothing else. A Pause
/// button wired to `setState(paused)` would show a banner, change the menu
/// label, and let the engine go on expecting a run every day — banking a miss
/// a day for the whole pause, silently. So the assertion that matters is not
/// "the flag is set", it is **"no paused day is ever MISSED"**, resolved
/// through the real engine graph past the pause.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  late Harness h;
  setUp(() => h = Harness());
  tearDown(() => h.dispose());

  Future<String> daily(Harness on, {String name = 'Running'}) =>
      on.repo.createCommitment(
        name: name,
        frequency: const Frequency.daily(),
        startedOn: d(2026, 8, 1),
        nowUtc: on.nowUtc,
      );

  group('what a pause does to accounting', () {
    test('no day inside a closed pause is ever missed', () async {
      final id = await daily(h);
      await h.repo.pauseCommitment(
        commitmentId: id,
        from: d(2026, 8, 10),
        to: d(2026, 8, 20),
      );

      final resolved = await h.resolutionFor(
        CivilDateRange(d(2026, 8, 1), d(2026, 8, 27)),
        id,
      );
      final paused = resolved.where((r) =>
          r.occurrence.span.start >= d(2026, 8, 10) &&
          r.occurrence.span.start <= d(2026, 8, 20));

      expect(paused, isEmpty,
          reason: 'a paused day is NOT_EXPECTED — it yields no occurrence at '
              'all, so it cannot enter any denominator');
    });

    test('an open pause keeps the future from accruing misses', () async {
      // Seven weeks after the pause starts. This is the archive bug's shape:
      // the failure only appears once enough time has passed, and resolving
      // only up to the pause date would pass against a broken implementation.
      final late = Harness(at: '2026-09-29T10:00:00+05:30');
      addTearDown(late.dispose);
      final id = await daily(late);

      await late.repo.pauseCommitment(commitmentId: id, from: d(2026, 8, 10));

      final resolved = await late.resolutionFor(
        CivilDateRange(d(2026, 8, 10), d(2026, 9, 28)),
        id,
      );
      expect(resolved, isEmpty,
          reason: 'fifty days under an open pause, and not one of them may '
              'turn MISSED');
    });

    test('history before the pause is untouched', () async {
      final id = await daily(h);
      await h.repo.record(
        commitmentId: id,
        date: d(2026, 8, 5),
        kind: TrackingKind.done,
        nowUtc: h.nowUtc,
        label: 'done',
      );
      final range = CivilDateRange(d(2026, 8, 1), d(2026, 8, 9));
      final before = await h.resolutionFor(range, id);

      await h.repo.pauseCommitment(commitmentId: id, from: d(2026, 8, 10));
      final after = await h.resolutionFor(range, id);

      expect(after.length, before.length);
      for (var i = 0; i < before.length; i++) {
        expect(after[i].status, before[i].status);
        expect(after[i].credit, before[i].credit);
      }
    });

    test('resuming makes the days after it expected again', () async {
      final late = Harness(at: '2026-09-29T10:00:00+05:30');
      addTearDown(late.dispose);
      final id = await daily(late);

      await late.repo.pauseCommitment(commitmentId: id, from: d(2026, 8, 10));
      await late.repo.resumeCommitment(commitmentId: id, on: d(2026, 9, 1));

      final paused = await late.resolutionFor(
        CivilDateRange(d(2026, 8, 10), d(2026, 8, 31)),
        id,
      );
      expect(paused, isEmpty, reason: 'the pause window stays out');

      final resumed = await late.resolutionFor(
        CivilDateRange(d(2026, 9, 1), d(2026, 9, 28)),
        id,
      );
      expect(resumed, hasLength(28),
          reason: 'the day resumed on is expected again, and so is every day '
              'after it');
      expect(
        resumed.where((r) => r.status == OccurrenceStatus.missed),
        hasLength(28),
        reason: 'nothing was recorded, and those days closed — they are '
            'genuine misses, which is the proof the pause really ended',
      );
    });
  });

  group('at most one open pause', () {
    test('a second pause closes the first rather than overlapping', () async {
      final id = await daily(h);
      await h.repo.pauseCommitment(commitmentId: id, from: d(2026, 8, 10));
      await h.repo.pauseCommitment(commitmentId: id, from: d(2026, 8, 20));

      final pauses = (await h.repo.readAll()).pausesFor(id);
      expect(pauses.where((p) => p.isOpen), hasLength(1),
          reason: 'two open pauses would both cover every future day, and '
              'resuming would close only one — a state with no way out');

      final closed = pauses.firstWhere((p) => !p.isOpen);
      expect(closed.from, d(2026, 8, 10));
      expect(closed.to, d(2026, 8, 19),
          reason: 'the first pause ends the day before the second begins, so '
              'the two cover a contiguous stretch with no gap and no overlap');
    });

    test('a pause that would cover no day is deleted, not stored', () async {
      final id = await daily(h);
      await h.repo.pauseCommitment(commitmentId: id, from: d(2026, 8, 20));
      await h.repo.resumeCommitment(commitmentId: id, on: d(2026, 8, 20));

      expect((await h.repo.readAll()).pausesFor(id), isEmpty,
          reason: 'an end before its own start is a row every future reader '
              'would have to know to skip');
    });

    test('resuming when nothing is paused does nothing', () async {
      final id = await daily(h);
      expect(
        await h.repo.resumeCommitment(commitmentId: id, on: d(2026, 8, 20)),
        isNull,
      );
      expect((await h.repo.readAll()).pausesFor(id), isEmpty);
    });

    test('one commitment pausing does not pause another', () async {
      final running = await daily(h);
      final reading = await daily(h, name: 'Reading');

      await h.repo.pauseCommitment(commitmentId: running, from: d(2026, 8, 10));

      expect((await h.repo.readAll()).pausesFor(reading), isEmpty);
      final resolved = await h.resolutionFor(
        CivilDateRange(d(2026, 8, 10), d(2026, 8, 20)),
        reading,
      );
      expect(resolved, hasLength(11));
    });
  });

  group('the backup format', () {
    test('an open pause round-trips through export and import', () async {
      final id = await daily(h);
      await h.repo.pauseCommitment(commitmentId: id, from: d(2026, 8, 10));

      final json = await h.backupJson();
      expect(json, contains('"to": null'),
          reason: 'the key is written explicitly, so "still paused" and '
              '"field lost in a truncated write" are not the same bytes');

      final document = const BackupCodec().decode(json);
      expect(document.version, BackupDocument.currentVersion);
      final pause = document.pauses.single;
      expect(pause.from, d(2026, 8, 10));
      expect(pause.to, isNull);
      expect(pause.isOpen, isTrue);
    });

    test('a v1 file, whose pauses always carried a date, still imports', () {
      const json = '''
{
  "format": "riyaz.backup",
  "version": 1,
  "exportedAt": "2026-08-28T04:30:00.000Z",
  "settings": {
    "timezone": "Asia/Kolkata",
    "dayBoundaryHour": 4,
    "weekStartsOn": 1
  },
  "commitments": [],
  "schedules": [],
  "pauses": [
    {"id": "p1", "commitmentId": "c1", "from": "2026-08-10", "to": "2026-08-20"}
  ],
  "events": []
}
''';
      final document = const BackupCodec().decode(json);
      expect(document.pauses.single.to, d(2026, 8, 20));
      expect(document.pauses.single.isOpen, isFalse,
          reason: 'a dated pause must not be read as open-ended');
    });

    test('a hand-repaired file with the key deleted reads as open', () {
      const json = '''
{
  "format": "riyaz.backup",
  "version": 2,
  "exportedAt": "2026-08-28T04:30:00.000Z",
  "settings": {
    "timezone": "Asia/Kolkata",
    "dayBoundaryHour": 4,
    "weekStartsOn": 1
  },
  "commitments": [],
  "schedules": [],
  "pauses": [{"id": "p1", "commitmentId": "c1", "from": "2026-08-10"}],
  "events": []
}
''';
      // The file is meant to be repairable by hand, and someone deleting the
      // line is at least as likely as someone typing `null`.
      expect(const BackupCodec().decode(json).pauses.single.isOpen,
          isTrue);
    });

    test('a file from a newer format is refused rather than guessed at', () {
      final json = '''
{
  "format": "riyaz.backup",
  "version": ${BackupDocument.currentVersion + 1},
  "exportedAt": "2026-08-28T04:30:00.000Z",
  "settings": {
    "timezone": "Asia/Kolkata",
    "dayBoundaryHour": 4,
    "weekStartsOn": 1
  },
  "commitments": [], "schedules": [], "pauses": [], "events": []
}
''';
      expect(
        () => const BackupCodec().decode(json),
        throwsA(isA<BackupFormatException>()),
        reason: 'this refusal is what the version bump buys: a build that '
            'reads only v1 must not take a null "to" for a corrupt record',
      );
    });

    test('an open pause survives a wipe and restore', () async {
      final id = await daily(h);
      await h.repo.pauseCommitment(commitmentId: id, from: d(2026, 8, 10));
      final json = await h.backupJson();

      await h.wipe();
      expect((await h.repo.readAll()).commitments, isEmpty);

      await h.restore(json);
      final restored = (await h.repo.readAll()).pausesFor(id);
      expect(restored, hasLength(1));
      expect(restored.single.isOpen, isTrue,
          reason: 'the one field the new schema exists for must survive the '
              'round trip a lost phone depends on');
    });
  });

  group('on the detail screen', () {
    Future<void> open(WidgetTester tester, String id) async {
      await h.pump(tester, CommitmentDetailScreen(commitmentId: id));
    }

    Future<void> choose(WidgetTester tester, String label) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('pausing says what it means for scoring', (tester) async {
      final id = await daily(h);
      await open(tester, id);

      await choose(tester, 'Pause');

      expect(find.text('Paused. These days will not count as missed.'),
          findsOneWidget);
      expect(find.textContaining('Paused since'), findsOneWidget);
    });

    testWidgets('pausing from the menu actually stops the engine expecting',
        (tester) async {
      // The trap this whole file exists for. A Pause button wired to
      // `setState(paused)` passes every other test on this screen — the
      // banner appears, the menu flips to Resume — while the engine goes on
      // expecting a run every day and banking a miss for each one. So this
      // goes through the UI and then resolves seven weeks of history past the
      // pause, which is the only assertion the wrong implementation fails.
      final late = Harness(at: '2026-09-29T10:00:00+05:30');
      addTearDown(late.dispose);
      final id = await late.repo.createCommitment(
        name: 'Running',
        frequency: const Frequency.daily(),
        startedOn: d(2026, 8, 1),
        nowUtc: late.nowUtc,
      );
      await late.pump(tester, CommitmentDetailScreen(commitmentId: id));

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();

      final after = await late.resolutionFor(
        CivilDateRange(late.today, late.today.plusDays(60)),
        id,
      );
      expect(after, isEmpty,
          reason: 'paused days are NOT_EXPECTED; not one of them may resolve '
              'at all, let alone as MISSED');
    });

    testWidgets('the menu offers Resume once paused, not Pause again',
        (tester) async {
      final id = await daily(h);
      await open(tester, id);
      await choose(tester, 'Pause');

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Pause'), findsNothing);
    });

    testWidgets('undo takes the pause back off', (tester) async {
      final id = await daily(h);
      await open(tester, id);
      await choose(tester, 'Pause');

      await tester.tap(find.text('UNDO'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Paused since'), findsNothing);
      expect((await h.repo.readAll()).pausesFor(id), isEmpty);
    });

    testWidgets('resuming clears the banner and can be undone',
        (tester) async {
      final id = await daily(h);
      await h.repo.pauseCommitment(commitmentId: id, from: d(2026, 8, 20));
      await open(tester, id);
      expect(find.textContaining('Paused since'), findsOneWidget);

      await choose(tester, 'Resume');
      expect(find.text('Resumed from today.'), findsOneWidget);
      expect(find.textContaining('Paused since'), findsNothing);

      await tester.tap(find.text('UNDO'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Paused since'), findsOneWidget,
          reason: 'undo restores the state, not the row id');
    });

    testWidgets('an archived commitment is not also offered a pause',
        (tester) async {
      final id = await daily(h);
      await h.repo.archiveCommitment(id, d(2026, 8, 20));
      await open(tester, id);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Pause'), findsNothing,
          reason: 'its schedule is already closed; there is nothing to '
              'suspend, and two words for one state is worse than one');
      expect(find.text('Unarchive'), findsOneWidget);
    });
  });
}
