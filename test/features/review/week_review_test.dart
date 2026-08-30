import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/features/home/home_screen.dart';
import 'package:riyaz/features/review/week_review_screen.dart';
import 'package:riyaz/features/review/widgets/review_card.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/dates.dart';
import '../../support/harness.dart';

/// The period-close review — spec §64.
///
/// The rule this screen has to get right is the one every other screen spends
/// its time avoiding: it is the **only** surface allowed to state a final
/// verdict. Everywhere else refuses to score an open window. So the tests here
/// are mostly about the boundaries of that licence — that it reviews a week
/// that is genuinely over, that it says nothing when there is nothing to say,
/// and that it does not turn a description into a judgement.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  // Sunday 2026-08-30. The last closed week is Mon 17 – Sun 23 August, since
  // the week containing today began on Monday the 24th.
  late Harness h;
  setUp(() => h = Harness());
  tearDown(() => h.dispose());

  Future<String> daily(String name, {String icon = 'run'}) =>
      h.repo.createCommitment(
        name: name,
        frequency: const Frequency.daily(),
        startedOn: d(2026, 6, 1),
        nowUtc: h.nowUtc,
        icon: icon,
      );

  Future<void> record(String id, CivilDate date,
          [TrackingKind kind = TrackingKind.done]) =>
      h.repo.record(
        commitmentId: id,
        date: date,
        kind: kind,
        nowUtc: h.nowUtc,
        label: 'x',
      );

  /// Marks [days] of the closed week (1 = Monday 17th) done for [id].
  Future<void> weekOf(String id, List<int> days) async {
    for (final day in days) {
      await record(id, d(2026, 8, 16 + day));
    }
  }

  group('which week', () {
    testWidgets('reviews the week that is over, not the one in progress',
        (tester) async {
      final id = await daily('Running');
      await weekOf(id, [1, 2, 3, 4, 5]);
      await h.pump(tester, const WeekReviewScreen());

      expect(
        find.text('Monday, Aug 17 – Sunday, Aug 23'),
        findsOneWidget,
        reason: 'a period result is final only at period close, so the week '
            'in progress must never be reviewed',
      );
      // Five of seven days.
      expect(find.text('71%'), findsOneWidget);
      expect(find.text('Of 7 occurrences that were yours to make'),
          findsOneWidget);
    });

    testWidgets('a week with nothing expected says so rather than 0%',
        (tester) async {
      // A commitment that only starts after the week in question.
      await h.repo.createCommitment(
        name: 'Running',
        frequency: const Frequency.daily(),
        startedOn: d(2026, 8, 28),
        nowUtc: h.nowUtc,
      );
      await h.pump(tester, const WeekReviewScreen());

      expect(find.text('Nothing to review'), findsOneWidget);
      expect(find.text('0%'), findsNothing,
          reason: 'an empty denominator is not a bad week');
    });
  });

  group('what it reports', () {
    testWidgets('counts, with skipped kept out of the score', (tester) async {
      final id = await daily('Running');
      await weekOf(id, [1, 2, 3]);
      await record(id, d(2026, 8, 20), TrackingKind.partial);
      await record(id, d(2026, 8, 21), TrackingKind.skipped);
      await h.pump(tester, const WeekReviewScreen());

      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Partial'), findsOneWidget);
      expect(find.text('Missed'), findsOneWidget);
      // Same treatment as Insights: a skip never entered the denominator and
      // the row has to say so rather than sitting beside Missed as a fourth
      // outcome.
      expect(find.text('Skipped, not counted'), findsOneWidget);
      expect(find.text('Of 6 occurrences that were yours to make'),
          findsOneWidget);
    });

    testWidgets('names the best and hardest commitments', (tester) async {
      final strong = await daily('Running');
      final weak = await daily('Reading', icon: 'read');
      await weekOf(strong, [1, 2, 3, 4, 5, 6, 7]);
      await weekOf(weak, [1]);
      await h.pump(tester, const WeekReviewScreen());

      expect(find.text('WENT BEST'), findsOneWidget);
      expect(find.text('HARDEST'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Reading'), findsOneWidget);

      // "Hardest", never "needs attention". The spec's wording instructs; the
      // product principle two sections later says the app describes behaviour
      // and does not judge the user.
      expect(find.textContaining('attention'), findsNothing);
    });

    testWidgets('names nobody when there is only one commitment',
        (tester) async {
      final id = await daily('Running');
      await weekOf(id, [1, 2, 3]);
      await h.pump(tester, const WeekReviewScreen());

      expect(find.text('WENT BEST'), findsNothing,
          reason: 'best and hardest would be the same row');
    });

    testWidgets('names nobody when every commitment scored the same',
        (tester) async {
      final a = await daily('Running');
      final b = await daily('Reading', icon: 'read');
      await weekOf(a, [1, 2, 3]);
      await weekOf(b, [1, 2, 3]);
      await h.pump(tester, const WeekReviewScreen());

      // Picking a "hardest" out of a tie is the app inventing a judgement.
      expect(find.text('HARDEST'), findsNothing);
    });

    testWidgets('recovery is the last thing said, when it can be said at all',
        (tester) async {
      final id = await daily('Running');
      // A lapse that was recovered from, so recovery has a duration.
      for (final day in [1, 2, 3, 8, 9, 10, 20, 21, 22]) {
        await record(id, d(2026, 7, 1).plusDays(day));
      }
      await weekOf(id, [1, 2, 3]);
      await h.pump(tester, const WeekReviewScreen());

      expect(find.textContaining('You come back within'), findsOneWidget);
      expect(
        find.text('Recovering quickly matters more than never slipping.'),
        findsOneWidget,
      );
    });

    testWidgets('recovery is absent until a lapse has actually been closed',
        (tester) async {
      final id = await daily('Running');
      await weekOf(id, [1, 2, 3]);
      await h.pump(tester, const WeekReviewScreen());

      expect(find.textContaining('You come back within'), findsNothing,
          reason: 'zero would claim a resilience never demonstrated');
    });
  });

  group('the prompt on Today', () {
    testWidgets('appears when a closed week is unread', (tester) async {
      final id = await daily('Running');
      await weekOf(id, [1, 2, 3]);
      await h.pump(tester, const HomeScreen());

      expect(find.text('Last week is in'), findsOneWidget);
    });

    testWidgets('stays away when the week held nothing', (tester) async {
      await h.repo.createCommitment(
        name: 'Running',
        frequency: const Frequency.daily(),
        startedOn: d(2026, 8, 28),
        nowUtc: h.nowUtc,
      );
      await h.pump(tester, const HomeScreen());

      expect(find.byType(ReviewCard), findsOneWidget);
      expect(find.text('Last week is in'), findsNothing,
          reason: 'a new user must not be greeted by a verdict on a week '
              'before they installed the app');
    });

    testWidgets('goes away once the week has been read', (tester) async {
      final id = await daily('Running');
      await weekOf(id, [1, 2, 3]);
      await h.pump(tester, const WeekReviewScreen());

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      await h.pump(tester, const HomeScreen());
      expect(find.text('Last week is in'), findsNothing);
    });

    testWidgets('the dismissal survives a restart', (tester) async {
      final id = await daily('Running');
      await weekOf(id, [1, 2, 3]);
      await h.pump(tester, const WeekReviewScreen());
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Same database, fresh provider graph — which is what relaunching the
      // app is. A flag held in memory would fail here.
      await h.pump(tester, const HomeScreen());
      await tester.pumpAndSettle();
      expect(find.text('Last week is in'), findsNothing);
    });
  });
}
