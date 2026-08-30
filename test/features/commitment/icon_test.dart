import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/glyphs.dart';
import 'package:riyaz/data/backup/backup_codec.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/features/commitment/widgets/glyph_picker.dart';
import 'package:riyaz/features/home/home_screen.dart';
import 'package:riyaz/features/home/widgets/commitment_icon.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/dates.dart';
import '../../support/harness.dart';

/// The icon vocabulary, where it meets stored data and pixels.
///
/// The unit-level rules live in `test/domain/model/commitment_icon_test.dart`;
/// this is the part that can only be seen end to end — that a stored key is
/// drawn as a glyph, that an unrecognised mark is not thrown away, and that an
/// old backup lands as keys rather than emoji.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  late Harness h;
  setUp(() => h = Harness());
  tearDown(() => h.dispose());

  Future<String> add(String name, String? icon) => h.repo.createCommitment(
        name: name,
        frequency: const Frequency.daily(),
        startedOn: d(2026, 8, 1),
        nowUtc: h.nowUtc,
        icon: icon,
      );

  group('rendering', () {
    testWidgets('a stored key draws a glyph, not text', (tester) async {
      await add('Running', 'run');
      await h.pump(tester, const HomeScreen());

      expect(
        find.descendant(
          of: find.byType(CommitmentIcon),
          matching: find.byIcon(glyphFor('run')!),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(CommitmentIcon),
          matching: find.byType(Text),
        ),
        findsNothing,
        reason: 'the whole point was to stop drawing a pictogram as type',
      );
    });

    testWidgets('an unmigrated emoji still draws as a glyph', (tester) async {
      // Belt and braces against a database the v4 migration has not touched —
      // a row inserted by an older build, or restored from a raw file.
      await add('Running', '🏃');
      await h.pump(tester, const HomeScreen());

      expect(
        find.descendant(
          of: find.byType(CommitmentIcon),
          matching: find.byIcon(glyphFor('run')!),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a mark outside the vocabulary is drawn, not dropped',
        (tester) async {
      await add('Odd', '🦖');
      await h.pump(tester, const HomeScreen());

      expect(
        find.descendant(
          of: find.byType(CommitmentIcon),
          matching: find.text('🦖'),
        ),
        findsOneWidget,
        reason: "the mark is the user's; losing it silently is worse than one "
            'row looking different',
      );
    });

    testWidgets('a commitment with no icon still lines up with the rest',
        (tester) async {
      await add('Plain', null);
      await add('Running', 'run');
      await h.pump(tester, const HomeScreen());

      final finder = find.byType(CommitmentIcon);
      expect(finder, findsNWidgets(2));
      final widths = {
        for (var i = 0; i < 2; i++) tester.getSize(finder.at(i)).width,
      };
      expect(widths, hasLength(1),
          reason: 'a list where some rows are indented and others are not '
              'reads as a layout bug');
    });
  });

  group('the picker', () {
    testWidgets('offers the whole vocabulary and reports the key',
        (tester) async {
      String? chosen = 'unset';
      await h.pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: GlyphPicker(
              selected: null,
              onSelected: (key) => chosen = key,
            ),
          ),
        ),
      );

      expect(find.byIcon(glyphFor('run')!), findsOneWidget);
      await tester.tap(find.byIcon(glyphFor('run')!));
      expect(chosen, 'run', reason: 'the picker writes keys, never glyphs');
    });

    testWidgets('tapping the chosen mark again clears it', (tester) async {
      String? chosen = 'unset';
      await h.pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: GlyphPicker(
              selected: 'run',
              onSelected: (key) => chosen = key,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(glyphFor('run')!));
      expect(chosen, isNull, reason: 'no mark at all is a legitimate answer');
    });
  });

  group('backup', () {
    test('an old file lands as keys, so a restore converges', () {
      const json = '''
{
  "format": "riyaz.backup",
  "version": 1,
  "exportedAt": "2026-08-28T04:30:00.000Z",
  "settings": {
    "timezone": "Asia/Kolkata",
    "dayBoundaryHour": 4,
    "weekStartsOn": 1
  },
  "commitments": [
    {"id": "c1", "name": "Running", "icon": "\\ud83c\\udfc3",
     "startedOn": "2026-08-01", "state": "active"},
    {"id": "c2", "name": "Odd", "icon": "\\ud83e\\udd96",
     "startedOn": "2026-08-01", "state": "active"}
  ],
  "schedules": [], "pauses": [], "events": []
}
''';
      final decoded = const BackupCodec().decode(json);
      expect(decoded.commitments.first.icon, 'run');
      expect(decoded.commitments.last.icon, '🦖',
          reason: 'an unrecognised mark is kept verbatim, not normalised away');
    });

    test('a key written today survives its own round trip', () async {
      await add('Running', 'run');
      final json = await h.backupJson();
      expect(const BackupCodec().decode(json).commitments.single.icon, 'run');
    });
  });
}
