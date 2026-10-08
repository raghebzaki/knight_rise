import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:knight_rise/core/config/background_ids.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/platform/system_settings_launcher.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';
import 'package:knight_rise/core/theme/widgets/knight_card.dart';
import 'package:knight_rise/core/widgets/confirm_discard.dart';
import 'package:knight_rise/features/cycle/presentation/widgets/routine_presentation.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/routines/presentation/routine_editor_cubit.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Android notification channel id of [type] (see `NotificationChannelIds`).
String routineChannelId(RoutineType type) => switch (type) {
  RoutineType.hydration => NotificationChannelIds.hydration,
  RoutineType.stretch => NotificationChannelIds.stretch,
  RoutineType.eyeRest => NotificationChannelIds.eyeRest,
};

/// Editor for one routine. The cubit and launcher come from DI unless given
/// (tests).
class RoutineEditorPage extends StatelessWidget {
  const RoutineEditorPage({required this.type, super.key, this.cubit, this.launcher});

  final RoutineType type;
  final RoutineEditorCubit? cubit;
  final SystemSettingsLauncher? launcher;

  @override
  Widget build(BuildContext context) {
    final provided = cubit;
    final view = _RoutineEditorView(type: type, launcher: launcher ?? getIt<SystemSettingsLauncher>());
    return provided != null
        ? BlocProvider.value(value: provided, child: view)
        : BlocProvider(
            create: (_) {
              final created = getIt<RoutineEditorCubit>(param1: type);
              unawaited(created.load());
              return created;
            },
            child: view,
          );
  }
}

class _RoutineEditorView extends StatelessWidget {
  const _RoutineEditorView({required this.type, required this.launcher});

  final RoutineType type;
  final SystemSettingsLauncher launcher;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<RoutineEditorCubit>();
    return BlocBuilder<RoutineEditorCubit, RoutineEditorState>(
      builder: (context, state) {
        final draft = state.draft;
        return PopScope(
          canPop: !state.isDirty,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final discard = await confirmDiscard(
              context,
              title: l.routineEditorDiscardTitle,
              body: l.routineEditorDiscardBody,
              discardLabel: l.routineEditorDiscard,
              keepLabel: l.routineEditorKeepEditing,
            );
            if (discard && context.mounted) Navigator.of(context).pop();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(type.label(l)),
              actions: [
                TextButton(
                  key: const Key('saveButton'),
                  onPressed: state.canSave ? () => _save(context, cubit) : null,
                  child: Text(l.routineEditorSave),
                ),
                const SizedBox(width: KnightSpacing.sm),
              ],
            ),
            body: draft == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      KnightSpacing.lg,
                      KnightSpacing.sm,
                      KnightSpacing.lg,
                      KnightSpacing.xxl,
                    ),
                    children: [
                      KnightCard(
                        padding: EdgeInsets.zero,
                        child: SwitchListTile(
                          key: const Key('enabledSwitch'),
                          secondary: Icon(type.icon, color: context.knight.routineColor(type)),
                          title: Text(l.routineEditorEnabled),
                          value: draft.enabled,
                          onChanged: (v) => cubit.setEnabled(enabled: v),
                        ),
                      ),
                      const SizedBox(height: KnightSpacing.md),
                      _IntervalCard(type: type, draft: draft),
                      const SizedBox(height: KnightSpacing.md),
                      _TargetCard(type: type, draft: draft, waterPerTapMl: state.waterPerTapMl),
                      const SizedBox(height: KnightSpacing.md),
                      _ModeCard(draft: draft),
                      if (defaultTargetPlatform == TargetPlatform.android) ...[
                        const SizedBox(height: KnightSpacing.md),
                        KnightCard(
                          padding: EdgeInsets.zero,
                          child: ListTile(
                            key: const Key('soundRow'),
                            leading: const Icon(Icons.notifications_active_outlined),
                            title: Text(l.routineEditorSound),
                            subtitle: Text(l.routineEditorSoundHelp),
                            trailing: const Icon(Icons.open_in_new),
                            onTap: () => launcher.openChannelSettings(routineChannelId(type)),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }

  Future<void> _save(BuildContext context, RoutineEditorCubit cubit) async {
    final saved = await cubit.save();
    if (saved && context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }
}

class _IntervalCard extends StatelessWidget {
  const _IntervalCard({required this.type, required this.draft});

  final RoutineType type;
  final Routine draft;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final range = Routine.intervalRange(type);
    final value = draft.intervalMinutes.clamp(range.min, range.max);
    return KnightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.routineEditorInterval, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: KnightSpacing.xs),
          Text(l.routineEditorIntervalValue(draft.intervalMinutes), key: const Key('intervalLabel')),
          Slider(
            key: const Key('intervalSlider'),
            value: value.toDouble(),
            min: range.min.toDouble(),
            max: range.max.toDouble(),
            divisions: (range.max - range.min) ~/ RoutineEditorCubit.intervalStep,
            label: '$value',
            onChanged: (v) => context.read<RoutineEditorCubit>().setInterval(v.round()),
          ),
        ],
      ),
    );
  }
}

class _TargetCard extends StatelessWidget {
  const _TargetCard({required this.type, required this.draft, required this.waterPerTapMl});

  final RoutineType type;
  final Routine draft;
  final int waterPerTapMl;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<RoutineEditorCubit>();
    final text = Theme.of(context).textTheme;
    return KnightCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.routineEditorTarget, style: text.titleMedium),
                const SizedBox(height: KnightSpacing.xs),
                Text(l.routineEditorTargetValue(draft.dailyTarget), key: const Key('targetLabel')),
                if (type == RoutineType.hydration)
                  Text(
                    l.routineEditorHydrationTotal(waterPerTapMl, draft.dailyTarget * waterPerTapMl),
                    key: const Key('hydrationTotal'),
                    style: text.bodyMedium?.copyWith(color: context.knight.textMuted),
                  ),
              ],
            ),
          ),
          IconButton(
            key: const Key('targetMinus'),
            tooltip: l.routineEditorDecrease,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: draft.dailyTarget > RoutineEditorCubit.minTarget ? cubit.decrementTarget : null,
          ),
          IconButton(
            key: const Key('targetPlus'),
            tooltip: l.routineEditorIncrease,
            icon: const Icon(Icons.add_circle_outline),
            onPressed: draft.dailyTarget < RoutineEditorCubit.maxTarget ? cubit.incrementTarget : null,
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.draft});

  final Routine draft;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final rolling = draft.mode == ScheduleMode.rolling;
    return KnightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.routineEditorMode, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: KnightSpacing.sm),
          SegmentedButton<ScheduleMode>(
            key: const Key('modeSelector'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: ScheduleMode.rolling, label: Text(l.routineEditorRolling)),
              ButtonSegment(value: ScheduleMode.fixedGrid, label: Text(l.routineEditorFixed)),
            ],
            selected: {draft.mode},
            onSelectionChanged: (s) => context.read<RoutineEditorCubit>().setMode(s.first),
          ),
          const SizedBox(height: KnightSpacing.sm),
          Text(
            rolling ? l.routineEditorRollingHelp : l.routineEditorFixedHelp,
            key: const Key('modeHelp'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.knight.textMuted),
          ),
        ],
      ),
    );
  }
}
