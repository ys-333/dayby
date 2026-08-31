import 'package:riyaz/features/notifications/notification_gateway.dart';

/// In-memory [NotificationGateway] for tests.
///
/// Exists for the same reason `_InMemoryFileStore` does: widget tests run in a
/// fake-async zone where real platform I/O never completes, so a screen that
/// schedules during a `pumpAndSettle` hangs forever rather than failing.
///
/// It records rather than asserts, so a test can ask what was scheduled without
/// this class having an opinion about what should have been.
class FakeNotificationGateway implements NotificationGateway {
  FakeNotificationGateway({this.permissionGranted = true});

  /// What [ensurePermission] reports. Set false to exercise a denial.
  bool permissionGranted;

  /// Every notification currently pending, by id.
  final Map<int, ScheduledNotification> scheduled = {};

  /// How many times the whole set has been replaced — the count that catches a
  /// reschedule that silently stopped happening.
  int replaceCount = 0;

  int permissionRequests = 0;

  /// Ids passed to [cancel], in order.
  final List<int> cancelled = [];

  /// Makes [replaceAll] throw, to prove a reminder failure cannot take a
  /// tracking write down with it.
  bool throwOnSchedule = false;

  List<ScheduledNotification> get inFireOrder =>
      scheduled.values.toList()..sort((a, b) => a.fireAt.compareTo(b.fireAt));

  @override
  Future<bool> ensurePermission() async {
    permissionRequests++;
    return permissionGranted;
  }

  @override
  Future<void> replaceAll(List<ScheduledNotification> items) async {
    replaceCount++;
    if (throwOnSchedule) throw StateError('scheduling refused');
    scheduled
      ..clear()
      ..addEntries([for (final item in items) MapEntry(item.id, item)]);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  @override
  Future<void> cancelAll() async => scheduled.clear();

  @override
  Future<List<int>> pendingIds() async => scheduled.keys.toList()..sort();
}
