import 'package:riyaz/domain/time/clock.dart';

/// The real clock. Lives outside `lib/domain/` because reading ambient time is
/// exactly what domain code is forbidden from doing.
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}
