import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'router.dart';
import 'theme/riyaz_theme.dart';

class RiyazApp extends ConsumerWidget {
  const RiyazApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
