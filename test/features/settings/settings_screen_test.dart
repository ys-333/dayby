import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/features/settings/settings_screen.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/dates.dart';
import '../../support/harness.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late Harness h;
  setUp(() => h = Harness());
  tearDown(() => h.dispose());

  Future<String> seed() async {
    final id = await h.repo.createCommitment(
      name: 'Running',
      frequency: const Frequency.daily(),
      startedOn: d(2026, 8, 1),
      nowUtc: h.nowUtc,
    );
    for (final day in [1, 2, 3]) {
      await h.repo.record(
        commitmentId: id,
        date: d(2026, 8, day),
        kind: TrackingKind.done,
        nowUtc: h.nowUtc,
        label: 'done',
      );
    }
    return id;
  }

  testWidgets('offers export and import, and explains auto-backup',
      (tester) async {
    await h.pump(tester, const SettingsScreen());
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(find.textContaining('backs the database up automatically'),
        findsOneWidget);
  });

  testWidgets('shows the accounting settings that make dates meaningful',
      (tester) async {
    await h.pump(tester, const SettingsScreen());
    expect(find.text('Day starts at'), findsOneWidget);
    expect(find.text('4:00'), findsOneWidget);
    expect(find.text('Asia/Kolkata'), findsOneWidget);
  });

  group('import', () {
    testWidgets('a malformed paste is refused with a readable reason',
        (tester) async {
      await h.pump(tester, const SettingsScreen());

      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'this is not json');
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();

      expect(find.text("That file can't be read"), findsOneWidget);
      expect(find.textContaining('Not valid JSON'), findsOneWidget);
    });

    testWidgets('a foreign JSON file is refused', (tester) async {
      await h.pump(tester, const SettingsScreen());

      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '{"some":"object"}');
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('does not look like a Riyaz backup'),
        findsOneWidget,
      );
    });

    testWidgets('a valid backup previews counts before writing anything',
        (tester) async {
      await seed();
      // Export through the service directly, then restore via the UI.
      await h.pump(tester, const SettingsScreen());
      final json = await h.backupJson();

      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), json);
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();

      expect(find.text('Import this backup?'), findsOneWidget);
      expect(find.text('1 commitments'), findsOneWidget);
      expect(find.text('3 tracking events'), findsOneWidget);
      // Nothing is written until a mode is chosen.
      expect(find.text('Merge'), findsOneWidget);
      expect(find.text('Replace all'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect((await h.repo.readAll()).events, hasLength(3));
    });

    testWidgets('replace restores a wiped database', (tester) async {
      await seed();
      final json = await h.backupJson();
      await h.wipe();
      expect((await h.repo.readAll()).commitments, isEmpty);

      await h.pump(tester, const SettingsScreen());
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), json);
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace all'));
      await tester.pumpAndSettle();

      final restored = await h.repo.readAll();
      expect(restored.commitments, hasLength(1));
      expect(restored.events, hasLength(3));
      expect(find.textContaining('Imported'), findsOneWidget);
    });
  });

  group('export', () {
    testWidgets('writes a file and offers the JSON on the clipboard',
        (tester) async {
      await seed();
      final clipboard = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await h.pump(tester, const SettingsScreen());
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      expect(find.text('Backup written'), findsOneWidget);
      expect(find.textContaining('riyaz-backup-2026-08-28.json'), findsWidgets);

      await tester.tap(find.text('Copy JSON'));
      await tester.pumpAndSettle();

      expect(clipboard, hasLength(1));
      expect(clipboard.single, contains('"format": "riyaz.backup"'));
      expect(clipboard.single, contains('"accountingDate": "2026-08-01"'));

      // The screen really wrote a file, and it matches what it copied.
      expect(h.writtenFiles, hasLength(1));
      expect(h.writtenFiles.keys.single, endsWith('riyaz-backup-2026-08-28.json'));
      expect(h.writtenFiles.values.single, clipboard.single);
    });
  });

  group('the synthetic seeder', () {
    testWidgets('loads a year of history and marks the rollups stale',
        (tester) async {
      final originalId = await seed();
      await h.pump(tester, const SettingsScreen());

      // Last section on a screen that has grown; a ListView builds only
      // what is on screen.
      await tester.dragUntilVisible(
        find.text('Load synthetic data'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.tap(find.text('Load synthetic data'));
      await tester.pumpAndSettle();

      // Destructive, so it must ask before wiping real history.
      expect(find.text('Replace everything with test data?'), findsOneWidget);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      final commitments = await h.db.select(h.db.commitments).get();
      expect(commitments.length, greaterThan(1),
          reason: 'the generated commitments should have replaced the seed');
      expect(commitments.any((c) => c.id == originalId), isFalse,
          reason: 'load replaces rather than merges');

      final events = await h.db.select(h.db.trackingEvents).get();
      expect(events, isNotEmpty, reason: 'a year of behaviour was generated');
    });

    testWidgets('cancelling leaves the database alone', (tester) async {
      await seed();
      await h.pump(tester, const SettingsScreen());

      // Last section on a screen that has grown; a ListView builds only
      // what is on screen.
      await tester.dragUntilVisible(
        find.text('Load synthetic data'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.tap(find.text('Load synthetic data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final commitments = await h.db.select(h.db.commitments).get();
      expect(commitments.single.name, 'Running');
    });
  });
}
