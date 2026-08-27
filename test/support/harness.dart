import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/data/db/app_database.dart';
import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/domain/time/clock.dart';

/// Shared widget-test harness: a real in-memory database plus a frozen clock,
/// so every screen test exercises the genuine engine graph rather than mocks.
class Harness {
  Harness({String at = '2026-08-28T10:00:00+05:30'})
      : clock = FixedClock.iso(at),
        db = AppDatabase(NativeDatabase.memory()) {
    repo = TrackingRepository(db);
  }

  final FixedClock clock;
  final AppDatabase db;
  late final TrackingRepository repo;

  DateTime get nowUtc => clock.nowUtc();

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(clock),
        ],
        child: MaterialApp(home: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose() => db.close();
}
