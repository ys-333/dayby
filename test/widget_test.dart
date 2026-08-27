import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/app.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/data/db/app_database.dart';
import 'package:riyaz/domain/time/clock.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// Boots the real app — router, theme, provider graph — against an in-memory
/// database. Distinct from the home-screen tests: this is what catches wiring
/// that only breaks when the whole composition root is assembled.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  testWidgets('the app boots to the today screen', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(
            FixedClock.iso('2026-08-28T10:00:00+05:30'),
          ),
        ],
        child: const RiyazApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The shell renders with all three destinations and lands on tracking.
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Nothing to track yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
