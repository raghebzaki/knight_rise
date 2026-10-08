import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Bottom navigation around the tab routes (`/` Today, `/quest` Quest Log).
class AppShell extends StatelessWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        // Re-selecting the current tab returns it to its first page.
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.today_outlined),
            selectedIcon: const Icon(Icons.today),
            label: l.navToday,
          ),
          NavigationDestination(
            icon: const Icon(Icons.military_tech_outlined),
            selectedIcon: const Icon(Icons.military_tech),
            label: l.navQuestLog,
          ),
        ],
      ),
    );
  }
}
