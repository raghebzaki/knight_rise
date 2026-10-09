import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/feedback/haptics.dart';
import 'package:knight_rise/core/layout/adaptive_columns.dart';
import 'package:knight_rise/core/layout/window_size.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';
import 'package:knight_rise/core/theme/text_scale.dart';
import 'package:knight_rise/core/theme/widgets/knight_card.dart';
import 'package:knight_rise/core/theme/widgets/knight_ring.dart';
import 'package:knight_rise/core/widgets/knight_error_view.dart';
import 'package:knight_rise/features/cycle/presentation/pages/break_page.dart' show kWaterChoicesMl;
import 'package:knight_rise/features/cycle/presentation/widgets/routine_presentation.dart';
import 'package:knight_rise/features/quest_log/domain/entities/daily_summary.dart';
import 'package:knight_rise/features/quest_log/presentation/quest_log_cubit.dart';
import 'package:knight_rise/features/quest_log/presentation/widgets/rank_up_dialog.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// How long the water logger's Undo stays available.
const kWaterUndoWindow = Duration(seconds: 5);

/// Quest Log tab: today's rings, streak and rank, per-routine progress,
/// water logger and focus time.
class QuestLogPage extends StatefulWidget {
  const QuestLogPage({super.key, this.cubitFactory});

  /// Builds the page's [QuestLogCubit]; the DI container by default.
  final QuestLogCubit Function()? cubitFactory;

  @override
  State<QuestLogPage> createState() => _QuestLogPageState();
}

class _QuestLogPageState extends State<QuestLogPage> {
  late final QuestLogCubit _cubit = (widget.cubitFactory ?? getIt.get<QuestLogCubit>)()..start();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _cubit.refresh);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_cubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
        appBar: AppBar(title: Text(l.questLogTitle.toUpperCase(), style: Theme.of(context).textTheme.headlineSmall)),
        body: BlocBuilder<QuestLogCubit, QuestLogState>(
          builder: (context, state) => switch (state) {
            QuestLogState(status: QuestLogStatus.ready, :final view?) => _QuestLogBody(view: view),
            QuestLogState(status: QuestLogStatus.failure, :final error) => KnightErrorView(
              details: error,
              onRetry: _cubit.start,
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }
}

class _QuestLogBody extends StatelessWidget {
  const _QuestLogBody({required this.view});

  final QuestLogView view;

  @override
  Widget build(BuildContext context) {
    final today = view.today;
    final hydrationOn = today.routines.any((r) => r.type == RoutineType.hydration && r.enabled);
    // Day 1: nothing finalized and nothing done yet.
    final cleanSlate =
        view.history.isEmpty && view.streak.best == 0 && today.routines.every((r) => r.done == 0) && today.waterMl == 0;
    final leading = <Widget>[
      if (cleanSlate) ...[const _CleanSlate(), const SizedBox(height: KnightSpacing.lg)],
      _Hero(view: view),
      const SizedBox(height: KnightSpacing.lg),
    ];
    final details = <Widget>[
      for (final r in today.routines) ...[
        _RoutineProgressCard(today: today, routine: r, lastDoneAt: view.lastDoneAt[r.type]),
        const SizedBox(height: KnightSpacing.md),
      ],
      if (hydrationOn) ...[
        const SizedBox(height: KnightSpacing.sm),
        _WaterLogger(waterMl: today.waterMl),
        const SizedBox(height: KnightSpacing.lg),
      ],
      _FocusCard(todayMinutes: today.focusMinutes, weekMinutes: view.focusMinutesWeek),
    ];
    const padding = EdgeInsetsDirectional.fromSTEB(
      KnightSpacing.lg,
      KnightSpacing.sm,
      KnightSpacing.lg,
      KnightSpacing.xxl,
    );
    if (!context.isMultiPane) return ListView(padding: padding, children: [...leading, ...details]);
    // Hero on the start side, the detail cards beside it; each scrolls alone.
    return AdaptiveTwoColumn(
      start: ListView(padding: padding.copyWith(end: 0), children: leading),
      end: ListView(padding: padding.copyWith(start: 0), children: details),
    );
  }
}

/// "{measure} / {goal}" for a routine: ml for hydration, counts otherwise.
String routineMeasureText(AppLocalizations l, DailySummary day, RoutineDaySummary r) {
  final m = day.measureOf(r);
  return r.type == RoutineType.hydration ? l.waterProgress(m.value, m.goal) : l.progressOf(m.value, m.goal);
}

/// "45 min", "1 h 5 min".
String formatFocusMinutes(AppLocalizations l, int minutes) =>
    minutes < 60 ? l.durationMinutes(minutes) : l.durationHoursMinutes(minutes ~/ 60, minutes % 60);

class _Hero extends StatelessWidget {
  const _Hero({required this.view});

  final QuestLogView view;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = context.knight;
    final text = Theme.of(context).textTheme;
    final today = view.today;
    final percent = (today.overallProgress * 100).round();
    return KnightCard(
      chamfered: true,
      padding: const EdgeInsets.all(KnightSpacing.xl),
      child: Column(
        children: [
          KnightRing(
            segments: [
              for (final r in today.routines.where((r) => r.enabled))
                RingSegment(
                  progress: today.measureOf(r).fraction,
                  color: tokens.routineColor(r.type),
                  label: '${r.type.label(l)} ${routineMeasureText(l, today, r)}',
                ),
            ],
            center: Text('$percent%', style: text.displayMedium),
          ),
          const SizedBox(height: KnightSpacing.lg),
          _RankBadge(view: view),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.view});

  final QuestLogView view;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = context.knight;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final streak = view.streak;
    final rank = streak.rank;
    final next = rank.next;
    final today = view.today;
    final todayLine = !today.countsTowardStreak
        ? l.questRestDay
        : today.qualified
        ? l.questQualified
        : l.questGoal(today.thresholdPercent);

    return Semantics(
      container: true,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.military_tech_outlined, color: scheme.primary),
              const SizedBox(width: KnightSpacing.sm),
              Text(rankName(l, rank).toUpperCase(), key: const Key('quest-rank'), style: text.titleLarge),
            ],
          ),
          const SizedBox(height: KnightSpacing.xs),
          Text(l.streakDays(streak.current), key: const Key('quest-streak'), style: text.titleMedium),
          Text(
            [
              l.streakBest(streak.best),
              if (next != null) l.rankNext(rank.daysToNext(streak.current)!, rankName(l, next)) else l.rankTop,
            ].join(' · '),
            style: text.bodySmall?.copyWith(color: tokens.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KnightSpacing.sm),
          Text(
            todayLine,
            key: const Key('quest-today-line'),
            style: text.bodySmall?.copyWith(color: today.qualified ? tokens.success : null),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _CleanSlate extends StatelessWidget {
  const _CleanSlate();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return KnightCard(
      key: const Key('quest-clean-slate'),
      child: Row(
        children: [
          Icon(Icons.flag_outlined, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: KnightSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.questCleanSlateTitle, style: text.titleMedium),
                Text(l.questCleanSlateBody, style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutineProgressCard extends StatelessWidget {
  const _RoutineProgressCard({required this.today, required this.routine, required this.lastDoneAt});

  final DailySummary today;
  final RoutineDaySummary routine;
  final DateTime? lastDoneAt;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = context.knight;
    final text = Theme.of(context).textTheme;
    final color = routine.enabled ? tokens.routineColor(routine.type) : tokens.textMuted;
    final last = lastDoneAt;
    final status = !routine.enabled
        ? l.questDisabled
        : last == null
        ? l.questNotYet
        : l.questLastAt(DateFormat.Hm(Localizations.localeOf(context).toLanguageTag()).format(last));

    final measure = routineMeasureText(l, today, routine);
    final large = context.isLargeText;
    return KnightCard(
      key: Key('quest-routine-${routine.type.name}'),
      child: Row(
        children: [
          KnightRing(
            size: 48,
            strokeWidth: 5,
            segments: [RingSegment(progress: today.measureOf(routine).fraction, color: color)],
            center: Icon(routine.type.icon, size: 20, color: color),
          ),
          const SizedBox(width: KnightSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(routine.type.label(l), style: text.titleLarge),
                Text(status, style: text.bodySmall?.copyWith(color: tokens.textMuted)),
                // Large text: the value sits under the title instead of beside it.
                if (large) Text(measure, style: text.labelMedium),
              ],
            ),
          ),
          if (!large) Text(measure, style: text.labelMedium),
        ],
      ),
    );
  }
}

class _WaterLogger extends StatelessWidget {
  const _WaterLogger({required this.waterMl});

  final int waterMl;

  Future<void> _log(BuildContext context, int ml) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final cubit = context.read<QuestLogCubit>();
    try {
      final id = await cubit.logWater(ml);
      if (context.mounted) context.haptic(HapticKind.success);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l.waterLogged(ml)),
            duration: kWaterUndoWindow,
            // An action would otherwise keep the SnackBar until dismissed.
            persist: false,
            action: SnackBarAction(label: l.undo, onPressed: () => unawaited(cubit.undoWater(id))),
          ),
        );
    } on Object {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.waterLogFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = context.knight;
    final text = Theme.of(context).textTheme;
    return KnightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(RoutineType.hydration.icon, color: tokens.hydration),
              const SizedBox(width: KnightSpacing.sm),
              Expanded(child: Text(l.waterLoggerTitle, style: text.titleLarge)),
              Text(l.waterToday(waterMl), style: text.labelMedium),
            ],
          ),
          const SizedBox(height: KnightSpacing.md),
          Wrap(
            spacing: KnightSpacing.sm,
            runSpacing: KnightSpacing.sm,
            children: [
              for (final ml in kWaterChoicesMl)
                // Spoken as "Log 250 ml of water", not just "250 ml".
                Semantics(
                  label: l.waterLogAction(ml),
                  excludeSemantics: true,
                  button: true,
                  onTap: () => unawaited(_log(context, ml)),
                  child: ActionChip(
                    key: Key('water-$ml'),
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text(l.mlAmount(ml)),
                    onPressed: () => unawaited(_log(context, ml)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.todayMinutes, required this.weekMinutes});

  final int todayMinutes;
  final int weekMinutes;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = context.knight;
    final text = Theme.of(context).textTheme;
    Widget stat(String label, int minutes, Key key) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelSmall?.copyWith(color: tokens.textMuted)),
          Text(formatFocusMinutes(l, minutes), key: key, style: text.titleMedium),
        ],
      ),
    );
    return KnightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: KnightSpacing.sm),
              Text(l.focusTitle, style: text.titleLarge),
            ],
          ),
          const SizedBox(height: KnightSpacing.md),
          Row(
            children: [
              stat(l.focusToday, todayMinutes, const Key('focus-today')),
              stat(l.focusWeek, weekMinutes, const Key('focus-week')),
            ],
          ),
        ],
      ),
    );
  }
}
