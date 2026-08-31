import 'package:riyaz/features/home/today_view.dart';
import 'package:riyaz/features/review/week_review_controller.dart';

/// A composed notification: everything the platform layer needs, and no logic.
class ReminderText {
  const ReminderText({
    required this.title,
    required this.body,
    required this.lines,
  });

  final String title;

  /// The collapsed line. Plain names, so it stays readable at one line.
  final String body;

  /// The expanded form, one commitment per line, carrying period progress.
  final List<String> lines;

  @override
  String toString() => 'ReminderText($title / $body)';
}

/// Turns what the app knows into what the notification says.
///
/// **Lives in `lib/features/` rather than `lib/domain/`, correcting the spec.**
/// It reads `TodayView` and `WeekReview`, which are presentation models in this
/// layer, and `tool/check_arch.sh` rightly forbids the domain from importing
/// them. Inventing a parallel domain type whose only purpose was to dodge that
/// rule would have added machinery without adding a single test. Nothing here
/// needs a widget pumped: it is pure functions over plain objects.
///
/// Three rules govern every string below, and they are why this is a unit
/// rather than a `String.format` at the call site:
///
/// * **Informational, never evaluative.** State what is true. No "don't break
///   your streak", no guilt clause. This is the same product stance that made
///   streaks deliberately not the headline metric — a notification that scolds
///   gets the app uninstalled, and the history is the asset.
/// * **Never speak with nothing to say.** A null return means *post nothing*.
///   "Nothing due today" is noise, and noise is how an app teaches its user to
///   swipe without reading.
/// * **Name the commitments.** A bare count can outlive its truth; a list and
///   the count derived from it go stale together or not at all.
abstract final class ReminderCopy {
  /// Today's reminder, or null when there is nothing worth saying.
  ///
  /// One rule covers every silent case at once: only *pending* items are worth
  /// a reminder. A day that is empty, fully done, entirely skipped or entirely
  /// paused has none, and so produces no notification.
  static ReminderText? daily(TodayView view) {
    final pending = view.items.where((item) => item.isPending).toList();
    if (pending.isEmpty) return null;

    final names = [for (final item in pending) item.commitment.name];

    return ReminderText(
      title: pending.length <= 3
          ? 'Today'
          : 'Today · ${pending.length} commitments',
      body: names.join(', '),
      lines: [for (final item in pending) _describe(item)],
    );
  }

  /// The week that just closed, or null when the week has no result.
  ///
  /// [previousPercent] is the week before it, when one exists — a new install
  /// has no comparison to draw and must not invent one.
  static ReminderText? weeklyReview(
    WeekReview review, {
    int? previousPercent,
  }) {
    // A week in which nothing was expected has nothing to report, and a review
    // opening with "0%" over an empty denominator is worse than no review.
    if (!review.hasResult) return null;
    final percent = review.summary.percent;
    if (percent == null) return null;

    final clauses = <String>[];

    // A decline is stated as a fact and never as a verdict: "Down from 78%" is
    // information the user can act on; "you slipped" is the app judging them.
    if (previousPercent != null && previousPercent != percent) {
      clauses.add(percent > previousPercent
          ? 'Up from $previousPercent%.'
          : 'Down from $previousPercent%.');
    }

    // `namesAreMeaningful` is the review controller's own judgement — with one
    // commitment, or with several tied, naming a strongest would be the app
    // inventing a distinction out of a tie. It must not be second-guessed here.
    if (review.namesAreMeaningful) {
      clauses.add('Strongest: ${review.best!.commitment.name}.');
    }

    return ReminderText(
      title: 'Last week — $percent%',
      body: clauses.isEmpty ? 'Tap to see the week.' : clauses.join(' '),
      lines: clauses.isEmpty ? const ['Tap to see the week.'] : clauses,
    );
  }

  /// One expanded line. Period rows carry their progress, because that is the
  /// number deciding whether today matters for them at all.
  static String _describe(TodayItem item) {
    final label = item.periodLabel;
    if (item.isPeriod && label != null) {
      return '${item.commitment.name}  ·  ${item.completed}/${item.target} $label';
    }
    return item.commitment.name;
  }
}
