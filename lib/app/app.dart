import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/notifications/notification_gateway.dart';
import '../features/notifications/reminder_scheduler.dart';
import 'providers.dart';
import 'router.dart';
import 'theme/riyaz_theme.dart';

class RiyazApp extends ConsumerStatefulWidget {
  const RiyazApp({super.key});

  @override
  ConsumerState<RiyazApp> createState() => _RiyazAppState();
}

class _RiyazAppState extends ConsumerState<RiyazApp> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();

    // Rescheduling on resume is one half of what keeps a pre-rendered
    // notification honest — the other half is the tracking-write hook. Both
    // exist because the text is composed days before it fires, so the only
    // defence is recomputing it at every moment the app is actually alive.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(reminderSchedulerProvider).reschedule(),
    );

    // Deferred past the first frame: this touches platform channels, and the
    // Today screen must not wait on a notification channel to paint.
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  Future<void> _prepare() async {
    final gateway = ref.read(notificationGatewayProvider);
    if (gateway is LocalNotificationGateway) {
      // A tapped reminder carries the route it should land on. The payload is
      // decided in Dart when the notification is composed, so the platform side
      // never has to know what screens exist.
      await gateway.initialize(onTap: router.go);
    }
    await ref.read(reminderSchedulerProvider).reschedule();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Riyaz',
      debugShowCheckedModeBanner: false,
      // Seeded from the database before the first frame — see `main()`. Both
      // themes are always supplied: on ThemeMode.system Flutter picks between
      // them as the platform setting changes, without the app rebuilding.
      themeMode: ref.watch(themeModeControllerProvider),
      theme: riyazTheme(Brightness.light),
      darkTheme: riyazTheme(Brightness.dark),
      routerConfig: router,
    );
  }
}
