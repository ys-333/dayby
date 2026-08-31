import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/features/notifications/notification_gateway.dart';
import 'package:riyaz/features/notifications/reminder_copy.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../support/fake_notification_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  ScheduledNotification item(int id, {int day = 1}) => ScheduledNotification(
        id: id,
        fireAt: tz.TZDateTime(
          tz.getLocation('Asia/Kolkata'),
          2026,
          9,
          day,
          8,
        ),
        text: const ReminderText(
          title: 'Today',
          body: 'Meditate',
          lines: ['Meditate'],
        ),
        route: '/',
      );

  group('the real gateway swallows every platform failure', () {
    // There is no platform under `flutter test`, so every method channel call
    // throws MissingPluginException. That makes this the honest test of the
    // rule `WidgetBridge` already follows: a revoked permission, an OEM that
    // drops alarms, or no notification support at all must never break the app
    // running in front of the user.
    late LocalNotificationGateway gateway;

    setUp(() => gateway = LocalNotificationGateway());

    test('initialize does not throw', () {
      expect(gateway.initialize(), completes);
    });

    test('ensurePermission reports false rather than throwing', () async {
      await expectLater(gateway.ensurePermission(), completion(isFalse));
    });

    test('replaceAll does not throw', () {
      expect(gateway.replaceAll([item(1)]), completes);
    });

    test('cancel and cancelAll do not throw', () {
      expect(gateway.cancel(1), completes);
      expect(gateway.cancelAll(), completes);
    });

    test('pendingIds returns empty rather than throwing', () async {
      await expectLater(gateway.pendingIds(), completion(isEmpty));
    });
  });

  group('the contract, exercised through the double', () {
    late FakeNotificationGateway gateway;

    setUp(() => gateway = FakeNotificationGateway());

    test('replaceAll replaces rather than appending', () async {
      await gateway.replaceAll([item(1), item(2, day: 2)]);
      await gateway.replaceAll([item(3, day: 3)]);

      expect(await gateway.pendingIds(), [3],
          reason: 'an append would let yesterday\'s reminders accumulate '
              'behind today\'s, and nothing would ever notice');
      expect(gateway.replaceCount, 2);
    });

    test('replacing with an empty list clears everything', () async {
      await gateway.replaceAll([item(1)]);
      await gateway.replaceAll(const []);
      expect(await gateway.pendingIds(), isEmpty);
    });

    test('cancel removes exactly one', () async {
      await gateway.replaceAll([item(1), item(2, day: 2), item(3, day: 3)]);
      await gateway.cancel(2);

      expect(await gateway.pendingIds(), [1, 3]);
      expect(gateway.cancelled, [2]);
    });

    test('cancelling an id that is not there is harmless', () async {
      await gateway.replaceAll([item(1)]);
      await gateway.cancel(99);
      expect(await gateway.pendingIds(), [1]);
    });

    test('a denial is reported, not thrown', () async {
      gateway.permissionGranted = false;
      expect(await gateway.ensurePermission(), isFalse);
      expect(gateway.permissionRequests, 1);
    });

    test('what was scheduled is inspectable, in fire order', () async {
      await gateway.replaceAll([item(3, day: 3), item(1, day: 1)]);
      expect(gateway.inFireOrder.map((i) => i.id), [1, 3]);
    });
  });
}
