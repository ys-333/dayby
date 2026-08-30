import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/app/app.dart';
import 'package:riyaz/app/shell.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/features/history/history_screen.dart';
import 'package:riyaz/features/home/home_screen.dart';
import 'package:riyaz/features/home/widgets/status_indicator.dart';
import 'package:riyaz/features/insights/insights_screen.dart';
import 'package:riyaz/features/settings/settings_screen.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/dates.dart';
import '../support/harness.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late Harness h;
  setUp(() => h = Harness());
  tearDown(() => h.dispose());

  Future<String> seed({String name = 'Running', String icon = '🏃'}) async {
    final id = await h.repo.createCommitment(
      name: name,
      frequency: const Frequency.daily(),
      startedOn: d(2026, 8, 1),
      nowUtc: h.nowUtc,
      icon: icon,
    );
    for (final day in [20, 21, 22, 24, 25]) {
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

  const screens = <String, Widget>{
    'home': HomeScreen(),
    'history': HistoryScreen(),
    'insights': InsightsScreen(),
    'settings': SettingsScreen(),
  };

  group('empty states', () {
    testWidgets('every screen renders with no data and no exception',
        (tester) async {
      for (final entry in screens.entries) {
        await h.pump(tester, entry.value);
        expect(tester.takeException(), isNull,
            reason: '${entry.key} threw on an empty database');
      }
    });

    testWidgets('empty states explain rather than showing a blank frame',
        (tester) async {
      await h.pump(tester, const HomeScreen());
      expect(find.text('Nothing to track yet.'), findsOneWidget);

      await h.pump(tester, const InsightsScreen());
      expect(find.text('Not enough data yet'), findsOneWidget);
    });

    testWidgets('nothing eligible shows a dash, never a fabricated zero',
        (tester) async {
      await h.pump(tester, const InsightsScreen());
      expect(find.text('0%'), findsNothing);
      expect(find.text('—'), findsWidgets);
    });
  });

  group('dark and light', () {
    testWidgets('every screen renders in both themes', (tester) async {
      await seed();
      for (final brightness in [Brightness.light, Brightness.dark]) {
        for (final entry in screens.entries) {
          await tester.pumpWidget(
            MaterialApp(
              theme: riyazTheme(brightness),
              home: h.scope(entry.value),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '${entry.key} threw in $brightness');
        }
      }
    });

    testWidgets('text keeps contrast against its own surface in dark mode',
        (tester) async {
      await seed();
      await tester.pumpWidget(
        MaterialApp(
          theme: riyazTheme(Brightness.dark),
          home: h.scope(const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Nothing may be painted with an explicit hard-coded black or white,
      // which is how a widget ends up invisible when the theme flips.
      final texts = tester.widgetList<Text>(find.byType(Text));
      for (final t in texts) {
        final color = t.style?.color;
        if (color == null) continue;
        expect(color, isNot(const Color(0xFF000000)),
            reason: 'hard-coded black disappears on a dark surface');
      }
    });
  });

  group('rotation and screen size', () {
    Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await h.pump(tester, child);
    }

    testWidgets('portrait, landscape and a small phone all render',
        (tester) async {
      await seed();
      const sizes = {
        'portrait': Size(400, 800),
        'landscape': Size(800, 400),
        'small': Size(320, 568),
      };
      for (final entry in screens.entries) {
        for (final size in sizes.entries) {
          await pumpAt(tester, size.value, entry.value);
          expect(tester.takeException(), isNull,
              reason: '${entry.key} threw at ${size.key}');
        }
      }
    });

    testWidgets('a very large text scale does not break layout',
        (tester) async {
      await seed();
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final entry in screens.entries) {
        await tester.pumpWidget(
          MediaQuery(
            // Accessibility setting many people actually use.
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: MaterialApp(home: h.scope(entry.value)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: '${entry.key} overflowed at 1.8x text scale');
      }
    });
  });

  group('accessibility', () {
    testWidgets('tracking rows carry a semantic label with their state',
        (tester) async {
      await seed();
      await h.pump(tester, const HomeScreen());

      final handle = tester.ensureSemantics();
      // The row announces what it is and where it stands, not just its name.
      expect(
        find.bySemanticsLabel(RegExp(r'Running, .*')),
        findsWidgets,
      );
      handle.dispose();
    });

    testWidgets('calendar cells announce their date and result',
        (tester) async {
      await seed();
      await h.pump(tester, const HistoryScreen());

      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel(RegExp(r'2026-08-25, .*')), findsWidgets);
      // A future day must announce that it has not happened, not a failure.
      expect(find.bySemanticsLabel(RegExp(r'2026-08-31, not yet')), findsWidgets);
      handle.dispose();
    });

    testWidgets('tap targets meet the minimum size', (tester) async {
      await seed();
      await h.pump(tester, const HomeScreen());

      final handle = tester.ensureSemantics();
      // Material's own guideline is 48x48; below that the row is hard to hit
      // for the one-tap flow the whole product depends on.
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('text contrast meets the guideline', (tester) async {
      await seed();
      await h.pump(tester, const HomeScreen());
      final handle = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });

  group('navigation', () {
    testWidgets('every tab is reachable and renders', (tester) async {
      await seed();
      await h.pump(tester, const AppShell());

      for (final label in ['History', 'Insights', 'Settings', 'Today']) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$label tab threw');
      }
    });

    testWidgets('the app boots end to end', (tester) async {
      await seed();
      await h.pumpApp(tester, const RiyazApp());
      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('tapping the Today tab comes back to today', (tester) async {
      await seed();
      await h.pump(tester, const AppShell());

      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      expect(find.text('Thursday, Aug 27'), findsOneWidget,
          reason: 'browsed back a day');

      await tester.tap(find.text('Insights').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Today').last);
      await tester.pumpAndSettle();

      // Scoped to the screen: the nav destination is also labelled "Today",
      // and the day bar says "Today" rather than the date once it is on the
      // current day.
      expect(
        find.descendant(
          of: find.byType(HomeScreen),
          matching: find.text('Today'),
        ),
        findsOneWidget,
        reason: 'Today should mean today, not the day left on screen',
      );
      expect(find.text('Thursday, Aug 27'), findsNothing);
    });

    testWidgets('a calendar day still opens that day on the tracking tab',
        (tester) async {
      await seed();
      await h.pump(tester, const AppShell());

      await tester.tap(find.text('History').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();

      // Week of Aug 24-30, Monday first: index 2 is Wednesday the 26th.
      await tester.tap(find.byType(StatusIndicator).at(2));
      await tester.pumpAndSettle();

      expect(find.text('Wednesday, Aug 26'), findsOneWidget,
          reason: 'the drill-down sets the tab directly and keeps its date');
    });

    testWidgets('the per-commitment screen is reachable from a long press',
        (tester) async {
      await seed();
      await h.pumpApp(tester, const RiyazApp());

      await tester.longPress(find.text('Running'));
      await tester.pumpAndSettle();
      expect(find.text('View details'), findsOneWidget,
          reason: 'the only route into the detail screen');

      await tester.tap(find.text('View details'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('MOMENTUM'), findsOneWidget,
          reason: 'the detail screen should be showing its stats');
    });
  });
}
