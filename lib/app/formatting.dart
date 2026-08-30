import 'package:riyaz/domain/time/civil_date.dart';

/// Date labels without an i18n dependency.
///
/// The app is single-locale for V1; pulling in `intl` for seven weekday names
/// would cost more than it returns. Swap this file for `DateFormat` if the app
/// is ever localised.
const List<String> _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String weekdayName(CivilDate date) => _weekdays[date.weekday - 1];

String shortMonth(CivilDate date) => _months[date.month - 1];

/// "Aug 28"
String dayLabel(CivilDate date) => '${shortMonth(date)} ${date.day}';

/// "Friday, Aug 28"
String fullDayLabel(CivilDate date) =>
    '${weekdayName(date)}, ${dayLabel(date)}';

/// Small counts read as words; large ones stay numerals.
///
/// "Three left today" is a sentence. "Twelve left today" is a sentence nobody
/// wants to read about their own morning, and past about six the word is
/// slower to parse than the digit.
const List<String> _smallNumbers = [
  'Nothing', 'One', 'Two', 'Three', 'Four', 'Five', 'Six',
];

String countWord(int n) =>
    n >= 0 && n < _smallNumbers.length ? _smallNumbers[n] : '$n';

/// The day's headline: **a count down to zero, never a score.**
///
/// A percentage of a day still being lived is a verdict delivered early — at
/// nine in the morning "17%" is a failing grade for a day that has barely
/// started. A count of what is left is a task, it shrinks as the day goes, and
/// it has an unambiguous best value.
///
/// [left] counts only open *daily* rows. A period target cannot be late on a
/// Tuesday, so it is never part of what is "left today".
///
/// A closed day gets a tally instead. The no-scoring rule protects a day the
/// user can still act on; once it is over, the count is a fact about what
/// happened rather than a judgement delivered mid-effort.
String dayHeadline({
  required int left,
  required int done,
  required int expected,
  required bool isToday,
}) {
  if (!isToday) {
    if (expected == 0) return 'Nothing was due';
    return '$done of $expected done';
  }
  if (expected == 0) return 'Nothing due today';
  if (left == 0) return 'Done for today';
  return '${countWord(left)} left today';
}

/// "Books", "Books and Swim", "Books, Swim and Long walk".
String joinNames(List<String> names) => switch (names.length) {
      0 => '',
      1 => names.single,
      2 => '${names[0]} and ${names[1]}',
      _ => '${names.sublist(0, names.length - 1).join(', ')} '
          'and ${names.last}',
    };
