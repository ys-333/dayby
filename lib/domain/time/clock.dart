/// The only way domain code learns the current time.
///
/// `lib/domain/` must never call `DateTime.now()` — `tool/check_arch.sh`
/// enforces that. The real implementation lives outside the domain (see
/// `lib/data/system_clock.dart`); tests use [FixedClock].
abstract interface class Clock {
  DateTime nowUtc();
}

/// A clock frozen at one instant. Pure, so it belongs in the domain.
class FixedClock implements Clock {
  const FixedClock(this.instant);

  /// Convenience for tests: `FixedClock.iso('2026-08-27T23:45:00+05:30')`.
  factory FixedClock.iso(String isoInstant) =>
      FixedClock(DateTime.parse(isoInstant));

  final DateTime instant;

  @override
  DateTime nowUtc() => instant.toUtc();
}
