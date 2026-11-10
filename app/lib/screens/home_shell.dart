import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/app_texts.dart';
import 'more_screen.dart';
import 'plan_screen.dart';
import 'stats_screen.dart';
import 'today_screen.dart';
import 'trends_screen.dart';

/// Rahmen der App: fünf Tabs unten, auf breiten Bildschirmen als Seitenleiste.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Wechselt von einer Unterseite aus den Tab (z. B. „Account verbinden“).
  static void goToTab(BuildContext context, int index) => context.findAncestorStateOfType<_HomeShellState>()?._select(index);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = [
    (icon: Icons.today_outlined, selected: Icons.today, label: T.tabToday),
    (icon: Icons.bar_chart_outlined, selected: Icons.bar_chart, label: T.tabStats),
    (icon: Icons.trending_up, selected: Icons.trending_up, label: T.tabTrends),
    (icon: Icons.lightbulb_outline, selected: Icons.lightbulb, label: T.tabPlan),
    (icon: Icons.more_horiz, selected: Icons.more_horiz, label: T.tabMore),
  ];

  void _select(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppConfig.wideLayoutBreakpoint;
    // IndexedStack behält Scroll-Position und Eingaben je Tab.
    final body = IndexedStack(index: _index, children: const [TodayScreen(), StatsScreen(), TrendsScreen(), PlanScreen(), MoreScreen()]);
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              child: NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final t in _tabs)
                    NavigationRailDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selected), label: Text(t.label)),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [for (final t in _tabs) NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selected), label: t.label)],
      ),
    );
  }
}
