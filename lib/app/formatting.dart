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

/// Greeting keyed to the wall-clock hour of the moment, not the accounting day.
String greetingFor(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}
