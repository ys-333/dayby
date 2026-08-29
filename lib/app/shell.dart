import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riyaz/features/history/history_screen.dart';
import 'package:riyaz/features/home/home_screen.dart';
import 'package:riyaz/features/home/today_controller.dart';
import 'package:riyaz/features/insights/insights_screen.dart';
import 'package:riyaz/features/settings/settings_screen.dart';

part 'shell.g.dart';

/// Which tab the shell is showing. A provider rather than local state so one
/// screen can send the user to another — tapping a calendar day opens that day
/// on the tracking tab rather than duplicating the editing UI.
@riverpod
class SelectedTab extends _$SelectedTab {
  @override
  int build() => 0;

  void go(int index) => state = index;
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(selectedTabProvider);

    // Keeps the home-screen widget in step for as long as the app is open.
    // Watched here rather than in a screen so it survives tab switches; the
    // push itself is best-effort and never blocks the UI.
    ref.watch(widgetSyncProvider);

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [
          HomeScreen(),
          HistoryScreen(),
          InsightsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          // Tapping Today is how you get back to today: someone who browsed
          // into history should not find last Tuesday still on screen. The
          // calendar's day drill-down sets the tab directly, not through here,
          // so it keeps the date it asked for.
          if (i == 0) ref.read(selectedDateProvider.notifier).returnToToday();
          ref.read(selectedTabProvider.notifier).go(i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.check_circle_outline_rounded),
            selectedIcon: Icon(Icons.check_circle_rounded),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Insights',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
