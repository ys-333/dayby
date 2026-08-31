import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'app/app.dart';
import 'app/providers.dart';
import 'data/db/app_database.dart';
import 'data/db/connection.dart';
import 'data/repository/settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The timezone database must be loaded before any accounting calendar is
  // built — every stored date is interpreted through it.
  tzdata.initializeTimeZones();

  // Settings are read here, once, rather than by a provider. The accounting
  // calendar is built from them and the whole engine graph hangs off that, so
  // an async settings provider would make every downstream provider async too.
  // One await before the first frame keeps all of them synchronous.
  //
  // The database is opened here for the same reason and handed to the graph, so
  // that this read and the app share one connection rather than opening two
  // against the same file.
  final database = AppDatabase(openConnection());
  final settings = await SettingsRepository(database).load();

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        initialAppSettingsProvider.overrideWithValue(settings),
      ],
      child: const RiyazApp(),
    ),
  );
}
