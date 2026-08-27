import 'package:flutter/material.dart';

import 'router.dart';

class RiyazApp extends StatelessWidget {
  const RiyazApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Riyaz',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F6C51)),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F6C51),
          brightness: Brightness.dark,
        ),
      ),
      routerConfig: router,
    );
  }
}
