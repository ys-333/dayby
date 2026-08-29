import 'package:flutter/material.dart';

import 'router.dart';
import 'theme/riyaz_theme.dart';

class RiyazApp extends StatelessWidget {
  const RiyazApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Riyaz',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: riyazTheme(Brightness.light),
      darkTheme: riyazTheme(Brightness.dark),
      routerConfig: router,
    );
  }
}
