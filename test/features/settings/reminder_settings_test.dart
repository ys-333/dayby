import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/app/settings.dart';
import 'package:riyaz/data/repository/settings_repository.dart';
import 'package:riyaz/domain/notifications/reminder_settings.dart';
import 'package:riyaz/features/notifications/notification_gateway.dart';
import 'package:riyaz/features/notifications/reminder_settings_controller.dart';
import 'package:riyaz/features/settings/settings_screen.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/harness.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late Harness harness;

  setUp(() => harness = Harness());
  tearDown(() => harness.dispose());

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(harness.scope(
      const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 120, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  group('the stored vocabulary', () {
    test('a time round-trips', () {
      expect(ReminderPreference.decodeTime(ReminderPreference.encodeTime(8, 5)),
          (8, 5));
      expect(ReminderPreference.encodeTime(8, 5), '08:05');
    });

    test('an unreadable or impossible time falls back as a whole', () {
      // Returning a half-parsed time would schedule a reminder at an hour that
      // does not exist — which fails silently, and is far harder to notice than
      // a value that simply reverts to the default.
      expect(ReminderPreference.decodeTime(null), isNull);
      expect(ReminderPreference.decodeTime('breakfast'), isNull);
      expect(ReminderPreference.decodeTime('25:00'), isNull);
      expect(ReminderPreference.decodeTime('8:70'), isNull);
      expect(ReminderPreference.decodeTime('08'), isNull);
    });

    test('a missing flag reads as off, never as on', () {
      expect(ReminderPreference.decodeFlag(null), isFalse);
      expect(ReminderPreference.decodeFlag('yes'), isFalse);
      expect(ReminderPreference.decodeFlag('true'), isTrue);
    });
  });

  group('a fresh install', () {
    testWidgets('shows both reminders off', (tester) async {
      await pumpSettings(tester);
      await scrollTo(tester, find.text('Daily reminder'));

      final switches = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      expect(switches, hasLength(2));
      expect(switches.every((s) => s.value), isFalse,
          reason: 'a tracker that notifies before being asked to gets its '
              'notifications switched off at the OS level');
    });

    testWidgets('leaves the time row unreachable until something is on',
        (tester) async {
      await pumpSettings(tester);
      await scrollTo(tester, find.text('Remind me at'));

      final tile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Remind me at'),
          matching: find.byType(ListTile),
        ),
      );
      expect(tile.enabled, isFalse);
    });
  });

  group('enabling', () {
    testWidgets('asks the OS and stores the choice when granted',
        (tester) async {
      harness.notifications.permissionGranted = true;
      await pumpSettings(tester);
      await scrollTo(tester, find.text('Daily reminder'));

      await tester.tap(find.text('Daily reminder'));
      await tester.pumpAndSettle();

      expect(harness.notifications.permissionRequests, 1);
      final stored = await ReminderPreference.load(
        SettingsRepository(harness.db),
      );
      expect(stored.dailyEnabled, isTrue);
    });

    testWidgets('a refusal changes nothing and says why', (tester) async {
      harness.notifications.permissionGranted = false;
      await pumpSettings(tester);
      await scrollTo(tester, find.text('Daily reminder'));

      await tester.tap(find.text('Daily reminder'));
      await tester.pumpAndSettle();

      // Nothing stored: a toggle reading "on" while Android blocks delivery is
      // a lie the user cannot debug.
      final stored = await ReminderPreference.load(
        SettingsRepository(harness.db),
      );
      expect(stored.dailyEnabled, isFalse);

      final tile = tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text('Daily reminder'),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(tile.value, isFalse);
      expect(find.textContaining('system settings'), findsOneWidget);
    });

    testWidgets('turning off never asks for permission', (tester) async {
      harness.notifications.permissionGranted = true;
      await pumpSettings(tester);
      await scrollTo(tester, find.text('Daily reminder'));

      await tester.tap(find.text('Daily reminder'));
      await tester.pumpAndSettle();
      final afterEnable = harness.notifications.permissionRequests;

      await tester.tap(find.text('Daily reminder'));
      await tester.pumpAndSettle();

      expect(harness.notifications.permissionRequests, afterEnable,
          reason: 'switching a reminder off is not a request to be notified');
    });

    testWidgets('the weekly review is a separate choice', (tester) async {
      harness.notifications.permissionGranted = true;
      await pumpSettings(tester);
      await scrollTo(tester, find.text('Weekly review'));

      await tester.tap(find.text('Weekly review'));
      await tester.pumpAndSettle();

      final stored = await ReminderPreference.load(
        SettingsRepository(harness.db),
      );
      expect(stored.weeklyReviewEnabled, isTrue);
      expect(stored.dailyEnabled, isFalse);
    });
  });

  group('the controller', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(harness.db),
        clockProvider.overrideWithValue(harness.clock),
        initialAppSettingsProvider.overrideWithValue(const AppSettings()),
        notificationGatewayProvider.overrideWithValue(harness.notifications),
      ]);
      addTearDown(container.dispose);
    });

    test('a stored choice survives a restart', () async {
      await container
          .read(reminderSettingsControllerProvider.notifier)
          .setDailyEnabled(true);
      await container
          .read(reminderSettingsControllerProvider.notifier)
          .setTime(7, 30);

      final reloaded =
          await ReminderPreference.load(SettingsRepository(harness.db));
      expect(reloaded.dailyEnabled, isTrue);
      expect(reloaded.hour, 7);
      expect(reloaded.minute, 30);
    });

    test('a refusal leaves the stored state untouched', () async {
      harness.notifications.permissionGranted = false;

      final ok = await container
          .read(reminderSettingsControllerProvider.notifier)
          .setDailyEnabled(true);

      expect(ok, isFalse);
      expect(
        container.read(reminderSettingsControllerProvider),
        const ReminderSettings(),
      );
    });

    test('enabling schedules, disabling clears', () async {
      await container
          .read(reminderSettingsControllerProvider.notifier)
          .setDailyEnabled(true);
      final afterEnable = harness.notifications.replaceCount;
      expect(afterEnable, greaterThan(0));

      await container
          .read(reminderSettingsControllerProvider.notifier)
          .setDailyEnabled(false);

      expect(await harness.notifications.pendingIds(), isEmpty,
          reason: 'switching reminders off must clear what the platform is '
              'already holding, not just stop adding to it');
    });
  });
}
