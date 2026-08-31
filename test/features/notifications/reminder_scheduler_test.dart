import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/app/settings.dart';
import 'package:riyaz/data/db/app_database.dart';
import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/notifications/reminder_settings.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/domain/time/clock.dart';
import 'package:riyaz/features/notifications/notification_gateway.dart';
import 'package:riyaz/features/notifications/reminder_scheduler.dart';
import 'package:riyaz/features/notifications/reminder_settings_controller.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/fake_notification_gateway.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late TrackingRepository repo;
  late FakeNotificationGateway gateway;

  /// Tuesday morning, well before an 08:00 reminder.
  const nowIso = '2026-09-01T06:00:00+05:30';
  const today = CivilDate(2026, 9, 1);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TrackingRepository(db);
    gateway = FakeNotificationGateway();
  });

  tearDown(() => db.close());

  ProviderContainer boot({
    ReminderSettings reminders =
        const ReminderSettings(dailyEnabled: true, hour: 8),
    String at = nowIso,
  }) =>
      ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(FixedClock.iso(at)),
          initialAppSettingsProvider.overrideWithValue(const AppSettings()),
          initialReminderSettingsProvider.overrideWithValue(reminders),
          notificationGatewayProvider.overrideWithValue(gateway),
        ],
      );

  Future<void> addDaily(String name) => repo.createCommitment(
        name: name,
        frequency: const Frequency.daily(),
        startedOn: const CivilDate(2026, 8, 1),
        nowUtc: DateTime.parse(nowIso).toUtc(),
      );

  group('nothing enabled', () {
    test('clears the platform rather than leaving stale reminders', () async {
      await addDaily('Meditate');
      await gateway.replaceAll(const []);

      final container = boot(reminders: const ReminderSettings());
      addTearDown(container.dispose);
      await container.read(reminderSchedulerProvider).reschedule();

      expect(await gateway.pendingIds(), isEmpty);
    });
  });

  group('composing the set', () {
    test('a day with pending commitments is scheduled', () async {
      await addDaily('Meditate');

      final container = boot();
      addTearDown(container.dispose);
      await container.read(reminderSchedulerProvider).reschedule();

      expect(gateway.scheduled, isNotEmpty);
      expect(gateway.inFireOrder.first.text.body, contains('Meditate'));
    });

    test('the text names what the day actually holds', () async {
      await addDaily('Meditate');
      await addDaily('Read');

      final container = boot();
      addTearDown(container.dispose);
      await container.read(reminderSchedulerProvider).reschedule();

      final first = gateway.inFireOrder.first;
      expect(first.text.body, contains('Meditate'));
      expect(first.text.body, contains('Read'));
    });

    test('an empty database schedules nothing at all', () async {
      final container = boot();
      addTearDown(container.dispose);
      await container.read(reminderSchedulerProvider).reschedule();

      expect(gateway.scheduled, isEmpty,
          reason: 'a reminder listing no commitments is noise, and noise '
              'teaches the user to swipe without reading');
    });

    test('daily reminders route to Today', () async {
      await addDaily('Meditate');

      final container = boot();
      addTearDown(container.dispose);
      await container.read(reminderSchedulerProvider).reschedule();

      expect(gateway.inFireOrder.first.route, ReminderRoutes.today);
    });

    test('the review routes to the review screen', () async {
      await addDaily('Meditate');

      final container = boot(
        reminders: const ReminderSettings(hour: 8, weeklyReviewEnabled: true),
      );
      addTearDown(container.dispose);
      await container.read(reminderSchedulerProvider).reschedule();

      final review = gateway.inFireOrder.single;
      expect(review.route, ReminderRoutes.review);
    });

    test('a review scheduled before its week closes invites, not reports',
        () async {
      // The honest limit of pre-rendering: the reviewed week is still running
      // when the notification is handed to the platform, so its percentage does
      // not exist yet and composing one would be a guess.
      await addDaily('Meditate');

      final container = boot(
        reminders: const ReminderSettings(hour: 8, weeklyReviewEnabled: true),
      );
      addTearDown(container.dispose);
      await container.read(reminderSchedulerProvider).reschedule();

      final review = gateway.inFireOrder.single;
      expect(review.text.title, isNot(contains('%')));
      expect(review.text.body, contains('ready'));
    });
  });

  group('rescheduling is what keeps pre-rendered text honest', () {
    test('replaces rather than accumulating', () async {
      await addDaily('Meditate');

      final container = boot();
      addTearDown(container.dispose);
      final scheduler = container.read(reminderSchedulerProvider);

      await scheduler.reschedule();
      final firstIds = await gateway.pendingIds();
      await scheduler.reschedule();

      expect(await gateway.pendingIds(), firstIds);
      expect(gateway.replaceCount, greaterThanOrEqualTo(2));
    });

    test('a tracking write reschedules on its own', () async {
      await addDaily('Meditate');

      final container = boot();
      addTearDown(container.dispose);
      // Touching the rollup provider installs the write hook, exactly as the
      // running app does at startup. The write must then go through the
      // container's own repository — that is the instance the hook sits on.
      container.read(rollupRepositoryProvider);
      final wired = container.read(trackingRepositoryProvider);

      final before = gateway.replaceCount;
      await wired.record(
        commitmentId: (await repo.read(const CivilDateRange(today, today)))
            .commitments
            .first
            .id,
        date: today,
        kind: TrackingKind.done,
        nowUtc: DateTime.parse(nowIso).toUtc(),
        label: 'done',
      );

      expect(gateway.replaceCount, greaterThan(before),
          reason: 'a write can make pre-rendered text wrong, so it must '
              'recompute — this is one of only two moments that can');
    });

    test('finishing the day drops its reminder', () async {
      await addDaily('Meditate');
      final container = boot();
      addTearDown(container.dispose);
      final scheduler = container.read(reminderSchedulerProvider);

      await scheduler.reschedule();
      final todayId = gateway.inFireOrder.first.id;
      expect(gateway.scheduled.containsKey(todayId), isTrue);

      final commitment =
          (await repo.read(const CivilDateRange(today, today))).commitments.first;
      await repo.record(
        commitmentId: commitment.id,
        date: today,
        kind: TrackingKind.done,
        nowUtc: DateTime.parse(nowIso).toUtc(),
        label: 'done',
      );
      await scheduler.reschedule();

      expect(gateway.scheduled.containsKey(todayId), isFalse,
          reason: 'being reminded to do what you have already done is the '
              'worst failure this feature has');
    });

    test('changing the day boundary reschedules everything', () async {
      await addDaily('Meditate');
      final container = boot(
        reminders: const ReminderSettings(dailyEnabled: true, hour: 3),
      );
      addTearDown(container.dispose);
      final scheduler = container.read(reminderSchedulerProvider);

      await scheduler.reschedule();
      final before = gateway.inFireOrder.map((i) => i.id).toList();

      // A 03:00 reminder sits on the far side of the boundary, so moving the
      // boundary changes which accounting day each one is about — and the ids
      // are derived from that.
      await container
          .read(appSettingsControllerProvider.notifier)
          .update(const AppSettings(dayBoundaryHour: 2));
      await scheduler.reschedule();

      expect(gateway.inFireOrder.map((i) => i.id).toList(), isNot(before));
    });
  });

  test('a gateway failure never breaks the write that triggered it', () async {
    await addDaily('Meditate');
    final container = boot();
    addTearDown(container.dispose);
    container.read(rollupRepositoryProvider);
    final wired = container.read(trackingRepositoryProvider);

    gateway.throwOnSchedule = true;

    final commitment =
        (await repo.read(const CivilDateRange(today, today))).commitments.first;

    // The tracking event is the canonical record; the notification is a
    // convenience over the top of it. Losing the second must never lose the
    // first.
    await expectLater(
      wired.record(
        commitmentId: commitment.id,
        date: today,
        kind: TrackingKind.done,
        nowUtc: DateTime.parse(nowIso).toUtc(),
        label: 'done',
      ),
      completes,
    );

    final events = (await repo.read(const CivilDateRange(today, today))).events;
    expect(events, hasLength(1));
  });
}
