import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The timezone database must be loaded before any accounting calendar is
  // built — every stored date is interpreted through it.
  tzdata.initializeTimeZones();
  runApp(const ProviderScope(child: RiyazApp()));
}
