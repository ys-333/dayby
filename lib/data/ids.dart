import 'dart:math';

/// Generates unique local ids.
///
/// Deliberately not a uuid package dependency: these ids never leave the
/// device, and a monotonic prefix plus randomness is collision-safe at the
/// scale of one person's habit history while keeping the dependency list short.
class IdGenerator {
  IdGenerator([Random? random]) : _random = random ?? Random();

  final Random _random;
  int _counter = 0;

  String next(String prefix) {
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final salt = _random.nextInt(1 << 20);
    return '$prefix-$stamp-${_counter++}-$salt';
  }
}
