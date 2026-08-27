import 'package:riyaz/domain/time/civil_date.dart';

/// Terse date literal for tests. Also keeps `prefer_const_constructors` quiet,
/// since the arguments are not compile-time constants here.
CivilDate d(int year, int month, int day) => CivilDate(year, month, day);
