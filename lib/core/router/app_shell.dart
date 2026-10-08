import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/feedback/haptics.dart';
import 'package:knight_rise/features/quest_log/presentation/rank_up_cubit.dart';
import 'package:knight_rise/features/quest_log/presentation/widgets/rank_up_dialog.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Bottom navigation around the tab routes (`/` Today, `/quest` Quest Log,
/// `/history` History). Also hosts the rank-up celebration, so a pending
/// rank-up shows on whichever tab opens first.
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
    final scaffold = Scaffold(
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
          NavigationDestination(
            icon: const Icon(Icons.insights_outlined),
            selectedIcon: const Icon(Icons.insights),
            label: l.navHistory,
          ),
        ],
      ),
    );
    final cubit = _rankUp;
    if (cubit == null) return scaffold;
    return BlocListener<RankUpCubit, PendingRankUp?>(
      bloc: cubit,
      listenWhen: (previous, current) => current != null && previous == null,
      listener: (context, pending) => unawaited(_celebrate(pending!)),
      child: scaffold,
    );
  }
}
