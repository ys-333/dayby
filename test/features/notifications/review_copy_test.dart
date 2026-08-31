import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/analytics/consistency_summary.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/features/notifications/reminder_copy.dart';
import 'package:riyaz/features/review/week_review_controller.dart';

void main() {
  const week = CivilDateRange(CivilDate(2026, 8, 31), CivilDate(2026, 9, 6));

  Commitment commitment(String name) => Commitment(
        id: name.toLowerCase(),
        name: name,
        startedOn: const CivilDate(2026, 1, 1),
      );

  /// A summary scoring [done] out of [done] + [missed].
  ConsistencySummary summaryOf({required int done, required int missed}) =>
      ConsistencySummary(
        done: done,
        partial: 0,
        missed: missed,
        skipped: 0,
        pending: 0,
        weightedCompletion: done.toDouble(),
      );

  CommitmentWeek member(String name, {required int done, required int missed}) =>
      CommitmentWeek(
        commitment: commitment(name),
        summary: summaryOf(done: done, missed: missed),
      );

  WeekReview reviewOf({
    required int done,
    required int missed,
    CommitmentWeek? best,
    CommitmentWeek? hardest,
    int scored = 2,
  }) =>
      WeekReview(
        week: week,
        summary: summaryOf(done: done, missed: missed),
        best: best,
        hardest: hardest,
        averageRecoveryDays: null,
        scored: scored,
      );

  group('a week with nothing in it says nothing', () {
    test('an empty week produces no notification', () {
      final review = reviewOf(done: 0, missed: 0, scored: 0);
      expect(review.hasResult, isFalse);
      expect(ReminderCopy.weeklyReview(review), isNull,
          reason: 'a review opening with 0% over an empty denominator is worse '
              'than no review — and a new install must not be greeted with a '
              'verdict on a week before they had the app');
    });
  });

  group('the headline', () {
    test('it leads with the week\'s percentage', () {
      final text = ReminderCopy.weeklyReview(
        reviewOf(done: 21, missed: 4),
      )!;
      expect(text.title, 'Last week — 84%');
    });

    test('a perfect week is stated plainly, not celebrated', () {
      final text = ReminderCopy.weeklyReview(reviewOf(done: 10, missed: 0))!;
      expect(text.title, 'Last week — 100%');
    });
  });

  group('the comparison clause', () {
    test('an improvement is reported', () {
      final text = ReminderCopy.weeklyReview(
        reviewOf(done: 21, missed: 4),
        previousPercent: 78,
      )!;
      expect(text.body, contains('Up from 78%.'));
    });

    test('a decline is a fact, not a verdict', () {
      final text = ReminderCopy.weeklyReview(
        reviewOf(done: 21, missed: 4),
        previousPercent: 92,
      )!;
      expect(text.body, contains('Down from 92%.'));
      // Stating the number is information the user can act on. Naming them a
      // backslider is the app passing judgement, which it never does.
      expect(text.body.toLowerCase(), isNot(contains('slip')));
      expect(text.body.toLowerCase(), isNot(contains('worse')));
    });

    test('with no previous week, the clause is dropped entirely', () {
      final text = ReminderCopy.weeklyReview(reviewOf(done: 21, missed: 4))!;
      expect(text.body, isNot(contains('from')),
          reason: 'a new install has no comparison to draw and must not '
              'invent one');
    });

    test('an unchanged score reports no movement', () {
      final text = ReminderCopy.weeklyReview(
        reviewOf(done: 21, missed: 4),
        previousPercent: 84,
      )!;
      expect(text.body, isNot(contains('Up from')));
      expect(text.body, isNot(contains('Down from')));
    });
  });

  group('the strongest clause defers to the review\'s own judgement', () {
    test('it names the best when the review says that is meaningful', () {
      final review = reviewOf(
        done: 21,
        missed: 4,
        best: member('Meditate', done: 7, missed: 0),
        hardest: member('Gym', done: 2, missed: 5),
      );
      expect(review.namesAreMeaningful, isTrue);

      final text = ReminderCopy.weeklyReview(review, previousPercent: 78)!;
      expect(text.body, 'Up from 78%. Strongest: Meditate.');
    });

    test('with a single commitment it names no one', () {
      // Best and hardest would be the same row; the pair is nonsense.
      final review = reviewOf(
        done: 7,
        missed: 0,
        best: member('Meditate', done: 7, missed: 0),
        hardest: member('Meditate', done: 7, missed: 0),
        scored: 1,
      );
      expect(review.namesAreMeaningful, isFalse);

      final text = ReminderCopy.weeklyReview(review)!;
      expect(text.body, isNot(contains('Strongest')));
    });

    test('with everything tied it names no one', () {
      // Picking a "strongest" out of a tie is the app inventing a judgement.
      final review = reviewOf(
        done: 14,
        missed: 0,
        best: member('Meditate', done: 7, missed: 0),
        hardest: member('Read', done: 7, missed: 0),
      );
      expect(review.namesAreMeaningful, isFalse);

      final text = ReminderCopy.weeklyReview(review)!;
      expect(text.body, isNot(contains('Strongest')));
    });

    test('with both clauses dropped it still gives a reason to open', () {
      final text = ReminderCopy.weeklyReview(reviewOf(done: 21, missed: 4))!;
      expect(text.body, isNotEmpty);
      expect(text.body, 'Tap to see the week.');
    });
  });

  test('it never scolds', () {
    final text = ReminderCopy.weeklyReview(
      reviewOf(
        done: 5,
        missed: 20,
        best: member('Meditate', done: 4, missed: 1),
        hardest: member('Gym', done: 0, missed: 7),
      ),
      previousPercent: 90,
    )!;
    final all = '${text.title} ${text.body}';

    for (final scold in ['streak', "don't", 'fail', 'slip', 'should']) {
      expect(all.toLowerCase(), isNot(contains(scold)),
          reason: 'a bad week is exactly when the copy must not moralise');
    }
  });
}
