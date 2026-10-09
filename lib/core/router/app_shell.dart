import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/feedback/haptics.dart';
import 'package:knight_rise/core/layout/window_size.dart';
import 'package:knight_rise/core/shortcuts/shell_navigation.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/features/quest_log/presentation/rank_up_cubit.dart';
import 'package:knight_rise/features/quest_log/presentation/widgets/rank_up_dialog.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Adaptive navigation around the branch routes (`/` Today, `/quest` Quest
/// Log, `/history` History, `/settings` Settings): a bottom bar when compact,
/// a rail when medium or expanded, an extended sidebar when large (see
/// [WindowSizeClass]). Also hosts the rank-up celebration, so a pending
/// rank-up shows on whichever tab opens first.
///
/// Keyboard: the navigation and the content are separate focus traversal
/// groups, each in reading order. With a rail or sidebar Tab walks its
/// destinations first, then the page (an explicit order, so it holds in
/// right-to-left layouts too); with the bottom bar the page comes first and
/// the bar last, as on screen. The
/// app-wide shortcuts (Ctrl/Cmd+1..4) switch branches through [ShellNavigation].
class AppShell extends StatefulWidget {
  const AppShell({required this.shell, super.key, this.rankUpCubitFactory});

  final StatefulNavigationShell shell;

  /// Builds the [RankUpCubit]; DI by default. Without either, no celebration.
  final RankUpCubit Function()? rankUpCubitFactory;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final RankUpCubit? _rankUp = _resolveRankUp()?..start();
  late final AppLifecycleListener _lifecycle;
  bool _celebrating = false;
  ShellNavigation? _navigation;

  RankUpCubit? _resolveRankUp() {
    final factory = widget.rankUpCubitFactory;
    if (factory != null) return factory();
    return getIt.isRegistered<RankUpCubit>() ? getIt<RankUpCubit>() : null;
  }

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => _rankUp?.refresh());
  }

  @override
  void dispose() {
    _navigation?.detach(widget.shell);
    _lifecycle.dispose();
    unawaited(_rankUp?.close());
    super.dispose();
  }

  /// Shows the rank-up once and records it as soon as it is shown.
  Future<void> _celebrate(PendingRankUp pending) async {
    final cubit = _rankUp;
    if (_celebrating || cubit == null) return;
    _celebrating = true;
    unawaited(cubit.markSeen());
    context.haptic(HapticKind.celebrate);
    await showDialog<void>(
      context: context,
      builder: (_) => RankUpDialog(rank: pending.rank, days: pending.days),
    );
    _celebrating = false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final shell = widget.shell;
    // Keyboard shortcuts switch branches through this shell (see ShellNavigation).
    _navigation = ShellNavigationScope.maybeOf(context)?..attach(shell);
    final size = context.windowSizeClass;
    final destinations = _destinations(l);
    // Re-selecting the current destination returns it to its first page.
    void select(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);
    final Widget scaffold;
    if (size.usesRail) {
      final extended = size == WindowSizeClass.large;
      scaffold = Scaffold(
        // Explicit order: the rail's destinations come before the page whatever their pixel positions (reading
        // order alone would visit the page's app bar first), and each side keeps reading order inside.
        body: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(secondary: ReadingOrderTraversalPolicy()),
          child: Row(
            children: [
              FocusTraversalOrder(
                order: const NumericFocusOrder(0),
                child: SafeArea(
                  child: FocusTraversalGroup(
                    policy: ReadingOrderTraversalPolicy(),
                    child: NavigationRail(
                      selectedIndex: shell.currentIndex,
                      onDestinationSelected: select,
                      extended: extended,
                      minExtendedWidth: 256,
                      labelType: size == WindowSizeClass.expanded
                          ? NavigationRailLabelType.all
                          : NavigationRailLabelType.none,
                      leading: extended
                          ? Padding(
                              padding: const EdgeInsetsDirectional.only(bottom: KnightSpacing.md),
                              child: Text(l.appTitle, style: Theme.of(context).textTheme.titleMedium),
                            )
                          : null,
                      destinations: [
                        for (final d in destinations)
                          NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selectedIcon),
                            label: Text(d.label),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: FocusTraversalOrder(
                  order: const NumericFocusOrder(1),
                  child: FocusTraversalGroup(policy: ReadingOrderTraversalPolicy(), child: shell),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      scaffold = Scaffold(
        body: FocusTraversalGroup(policy: ReadingOrderTraversalPolicy(), child: shell),
        bottomNavigationBar: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: select,
            destinations: [
              for (final d in destinations)
                NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
            ],
          ),
        ),
      );
    }
    final cubit = _rankUp;
    if (cubit == null) return scaffold;
    return BlocListener<RankUpCubit, PendingRankUp?>(
      bloc: cubit,
      listenWhen: (previous, current) => current != null && previous == null,
      listener: (context, pending) => unawaited(_celebrate(pending!)),
      child: scaffold,
    );
  }

  /// The one destination list behind every layout, in branch order.
  List<({IconData icon, IconData selectedIcon, String label})> _destinations(AppLocalizations l) => [
    (icon: Icons.today_outlined, selectedIcon: Icons.today, label: l.navToday),
    (icon: Icons.military_tech_outlined, selectedIcon: Icons.military_tech, label: l.navQuestLog),
    (icon: Icons.insights_outlined, selectedIcon: Icons.insights, label: l.navHistory),
    (icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: l.navSettings),
  ];
}
