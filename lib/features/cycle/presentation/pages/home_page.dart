import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/config/flavor.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';
import 'package:knight_rise/core/theme/widgets/knight_card.dart';
import 'package:knight_rise/core/theme/widgets/knight_ring.dart';
import 'package:knight_rise/features/cycle/presentation/bloc/cycle_bloc.dart';
import 'package:knight_rise/features/cycle/presentation/widgets/countdown_text.dart';
import 'package:knight_rise/features/cycle/presentation/widgets/routine_presentation.dart';
import 'package:knight_rise/features/notifications/presentation/notification_permission_cubit.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/cycle_snapshot.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:knight_rise/features/settings/presentation/theme_cubit.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Daily dashboard: quest rings, next-up countdown, routine cards.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => context.read<CycleBloc>().add(const CycleRefreshRequested()));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.appTitle.toUpperCase(), style: text.headlineSmall),
            Text(l.tagline, style: text.labelSmall),
          ],
        ),
        actions: [
          if (Flavor.current.isDev)
            IconButton(
              tooltip: 'Diagnostics',
              icon: const Icon(Icons.bug_report_outlined),
              onPressed: () => context.push('/diagnostics'),
            ),
          if (Flavor.current.isDev)
            IconButton(
              tooltip: l.gallery,
              icon: const Icon(Icons.palette_outlined),
              onPressed: () => context.push('/gallery'),
            ),
          const _ThemeToggle(),
          const SizedBox(width: KnightSpacing.sm),
        ],
      ),
      body: BlocBuilder<CycleBloc, CycleState>(
        builder: (context, state) => switch (state) {
          CycleState(status: CycleStatus.ready, :final snapshot?) => _Dashboard(snapshot: snapshot),
          CycleState(status: CycleStatus.failure, :final error) => Center(child: Text(error ?? '')),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final variant = context.watch<ThemeCubit>().state;
    final amoled = variant == ThemeVariant.amoled;
    return IconButton(
      tooltip: amoled ? l.themeMidnight : l.themeAmoled,
      icon: Icon(amoled ? Icons.nightlight_outlined : Icons.contrast),
      onPressed: () => context.read<ThemeCubit>().toggle(),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.snapshot});

  final CycleSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(KnightSpacing.lg, KnightSpacing.sm, KnightSpacing.lg, KnightSpacing.xxl),
      children: [
        const _NotificationPermissionCard(),
        _QuestHero(snapshot: snapshot),
        const SizedBox(height: KnightSpacing.lg),
        _NextUpCard(snapshot: snapshot),
        const SizedBox(height: KnightSpacing.lg),
        for (final view in snapshot.routines) ...[
          _RoutineCard(view: view, snapshot: snapshot),
          const SizedBox(height: KnightSpacing.md),
        ],
      ],
    );
  }
}

/// Shown while notifications are off. Tapping Enable is the only place the
/// system permission dialog is triggered.
class _NotificationPermissionCard extends StatelessWidget {
  const _NotificationPermissionCard();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationPermissionCubit, NotificationPermissionState>(
      builder: (context, state) {
        if (!state.showPrompt) return const SizedBox.shrink();
        final l = AppLocalizations.of(context);
        final text = Theme.of(context).textTheme;
        final cubit = context.read<NotificationPermissionCubit>();
        return Padding(
          padding: const EdgeInsets.only(bottom: KnightSpacing.lg),
          child: KnightCard(
            glow: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.notifications_active_outlined, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: KnightSpacing.md),
                    Expanded(child: Text(l.notifPermissionTitle, style: text.titleLarge)),
                  ],
                ),
                const SizedBox(height: KnightSpacing.sm),
                Text(state.requestDenied ? l.notifPermissionBodyDenied : l.notifPermissionBody, style: text.bodyMedium),
                const SizedBox(height: KnightSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: cubit.dismiss, child: Text(l.notNow)),
                    const SizedBox(width: KnightSpacing.sm),
                    FilledButton(onPressed: cubit.request, child: Text(l.enable)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuestHero extends StatelessWidget {
  const _QuestHero({required this.snapshot});

  final CycleSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = context.knight;
    final text = Theme.of(context).textTheme;
    final percent = (snapshot.overallProgress * 100).round();

    return KnightCard(
      chamfered: true,
      padding: const EdgeInsets.all(KnightSpacing.xl),
      child: Column(
        children: [
          Text(l.questLog.toUpperCase(), style: text.titleLarge),
          const SizedBox(height: KnightSpacing.lg),
          KnightRing(
            segments: [
              for (final v in snapshot.routines.where((v) => v.routine.enabled))
                RingSegment(
                  progress: v.progress,
                  color: tokens.routineColor(v.type),
                  label: '${v.type.label(l)} ${l.progressOf(v.doneToday, v.routine.dailyTarget)}',
                ),
            ],
            center: Text('$percent%', style: text.displayMedium),
          ),
          const SizedBox(height: KnightSpacing.lg),
          Wrap(
            spacing: KnightSpacing.lg,
            runSpacing: KnightSpacing.sm,
            alignment: WrapAlignment.center,
            children: [
              for (final v in snapshot.routines.where((v) => v.routine.enabled))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(v.type.icon, size: 16, color: tokens.routineColor(v.type)),
                    const SizedBox(width: KnightSpacing.xs),
                    Text(l.progressOf(v.doneToday, v.routine.dailyTarget), style: text.labelMedium),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NextUpCard extends StatelessWidget {
  const _NextUpCard({required this.snapshot});

  final CycleSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final tokens = context.knight;
    final now = context.read<Clock>().now();

    final due = snapshot.routines.where((v) => v.status is StatusDue).toList();
    final next = snapshot.nextUp;

    if (due.isNotEmpty) {
      return KnightCard(
        glow: true,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.dueNow.toUpperCase(), style: text.labelMedium?.copyWith(color: tokens.warning)),
                  const SizedBox(height: KnightSpacing.xs),
                  Text(due.map((v) => v.type.label(l)).join(' + '), style: text.titleLarge),
                ],
              ),
            ),
            FilledButton(
              onPressed: () {
                final bloc = context.read<CycleBloc>();
                for (final v in due) {
                  bloc.add(RoutineCompleted(v.type));
                }
              },
              child: Text(l.claimBreak),
            ),
          ],
        ),
      );
    }

    if (!snapshot.onDuty || next == null) {
      final back = snapshot.nextWorkStart;
      return KnightCard(
        child: Row(
          children: [
            Icon(Icons.shield_moon_outlined, color: tokens.textMuted),
            const SizedBox(width: KnightSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.offDuty, style: text.titleLarge),
                  if (back != null) Text(l.offDutyNext(formatWhen(context, back, now)), style: text.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return KnightCard(
      glow: true,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.nextUp.toUpperCase(),
                  style: text.labelMedium?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(height: KnightSpacing.xs),
                Text(next.types.map((t) => t.label(l)).join(' + '), style: text.titleLarge),
                Text(formatWhen(context, next.fireAt, now), style: text.bodySmall),
              ],
            ),
          ),
          CountdownText(target: next.fireAt, style: text.displaySmall?.copyWith(fontSize: 28)),
        ],
      ),
    );
  }
}

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({required this.view, required this.snapshot});

  final RoutineView view;
  final CycleSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final tokens = context.knight;
    final color = tokens.routineColor(view.type);
    final now = context.read<Clock>().now();
    final enabled = view.routine.enabled;

    final statusLine = switch (view.status) {
      StatusDisabled() => l.disabled,
      StatusOffDuty() => l.offDuty,
      StatusDue() => l.dueNow,
      StatusSnoozed(:final until) => l.snoozedUntil(formatWhen(context, until, now)),
      StatusUpcoming(:final at) => at == null ? '' : '${l.nextUp} · ${formatWhen(context, at, now)}',
    };
    final isDue = view.status is StatusDue;

    return KnightCard(
      glow: isDue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KnightRing(
                size: 48,
                strokeWidth: 5,
                segments: [RingSegment(progress: view.progress, color: color)],
                center: Icon(view.type.icon, size: 20, color: color),
              ),
              const SizedBox(width: KnightSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(view.type.label(l), style: text.titleLarge),
                    Text(statusLine, style: text.bodySmall?.copyWith(color: isDue ? tokens.warning : null)),
                  ],
                ),
              ),
              Text(
                view.type == RoutineType.hydration
                    ? l.waterToday(snapshot.waterMlToday)
                    : l.progressOf(view.doneToday, view.routine.dailyTarget),
                style: text.labelMedium,
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: KnightSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: view.canSnooze && (isDue || view.status is StatusUpcoming)
                      ? () => context.read<CycleBloc>().add(RoutineSnoozed(view.type))
                      : null,
                  child: Text(l.snooze10),
                ),
                const SizedBox(width: KnightSpacing.sm),
                FilledButton(
                  onPressed: () => context.read<CycleBloc>().add(RoutineCompleted(view.type)),
                  child: Text(l.done),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
