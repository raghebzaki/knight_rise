import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';
import 'package:knight_rise/core/theme/text_scale.dart';
import 'package:knight_rise/core/theme/widgets/knight_card.dart';
import 'package:knight_rise/core/theme/widgets/knight_ring.dart';
import 'package:knight_rise/features/cycle/presentation/widgets/routine_presentation.dart';
import 'package:knight_rise/features/notifications/presentation/notification_permission_cubit.dart';
import 'package:knight_rise/features/onboarding/presentation/onboarding_cubit.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/settings/presentation/widgets/language_selector.dart';
import 'package:knight_rise/features/work_hours/domain/work_schedule_validation.dart';
import 'package:knight_rise/features/work_hours/domain/work_week.dart';
import 'package:knight_rise/features/work_hours/presentation/work_format.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// First-run setup ("Take the Oath"): four steps, one draft, saved at the end.
/// The cubit comes from DI.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final created = getIt<OnboardingCubit>();
        unawaited(created.load());
        return created;
      },
      child: const _OnboardingView(),
    );
  }
}

class _OnboardingView extends StatefulWidget {
  const _OnboardingView();

  @override
  State<_OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<_OnboardingView> {
  final _controller = PageController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (!_controller.hasClients) return;
    _controller.animateToPage(index, duration: KnightMotion.fast, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<OnboardingCubit, OnboardingState>(
      listenWhen: (a, b) => a.step != b.step,
      listener: (_, state) => _goTo(state.step.index),
      child: PopScope(
        // System back steps to the previous step; only the first step lets the
        // route (and so the app) close.
        canPop: context.select<OnboardingCubit, bool>((c) => c.state.step == OnboardingStep.welcome),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) context.read<OnboardingCubit>().back();
        },
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                const _Progress(),
                Expanded(
                  child: PageView(
                    controller: _controller,
                    // Steps only change through the cubit, so invalid steps
                    // cannot be skipped.
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      const _WelcomeStep(),
                      const _RoutinesStep(),
                      const _WorkHoursStep(),
                      const _OathStep(),
                    ].map((s) => _StepFrame(child: s)).toList(),
                  ),
                ),
                const _NavBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepFrame extends StatelessWidget {
  const _StepFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        KnightSpacing.xl,
        KnightSpacing.lg,
        KnightSpacing.xl,
        KnightSpacing.lg,
      ),
      child: child,
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final step = context.select<OnboardingCubit, int>((c) => c.state.step.index);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(KnightSpacing.xl, KnightSpacing.lg, KnightSpacing.xl, 0),
      child: Semantics(
        label: l.onboardingStepLabel(step + 1, OnboardingStep.values.length),
        child: ExcludeSemantics(
          child: Row(
            key: const Key('onboarding-progress'),
            children: [
              for (var i = 0; i < OnboardingStep.values.length; i++) ...[
                if (i > 0) const SizedBox(width: KnightSpacing.sm),
                Expanded(
                  child: AnimatedContainer(
                    key: Key('progress-segment-$i'),
                    duration: KnightMotion.fast,
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= step ? scheme.primary : scheme.outline,
                      borderRadius: BorderRadius.circular(KnightRadius.sm),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<OnboardingCubit>();
    final state = context.watch<OnboardingCubit>().state;
    final first = state.step == OnboardingStep.welcome;
    final last = state.step == OnboardingStep.oath;
    final onPrimary = last
        ? (state.isValid && !state.finishing ? () => unawaited(cubit.finish()) : null)
        : (state.canAdvance ? cubit.next : null);
    final primaryLabel = first
        ? l.onboardingBegin
        : last
        ? l.onboardingTakeOath
        : l.onboardingNext;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        KnightSpacing.xl,
        KnightSpacing.sm,
        KnightSpacing.xl,
        KnightSpacing.lg,
      ),
      child: Row(
        children: [
          if (!first) ...[
            OutlinedButton(
              key: const Key('onboarding-back'),
              onPressed: state.finishing ? null : cubit.back,
              child: Text(l.onboardingBack),
            ),
            const SizedBox(width: KnightSpacing.md),
          ],
          Expanded(
            child: FilledButton(
              key: const Key('onboarding-primary'),
              onPressed: onPrimary,
              child: state.finishing
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(primaryLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title, style: theme.textTheme.headlineMedium)),
        const SizedBox(height: KnightSpacing.sm),
        Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: context.knight.textMuted)),
        const SizedBox(height: KnightSpacing.xl),
      ],
    );
  }
}

// ---- Step 1: welcome (and language) ----------------------------------------

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tokens = context.knight;
    return Column(
      children: [
        // First thing on screen, so the rest of the flow reads in the chosen
        // language (and direction) from here on.
        Semantics(
          container: true,
          label: l.language,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The icon is decorative; at large text the selector needs the width.
              if (!context.isLargeText) ...[
                Icon(Icons.translate, size: 20, color: tokens.textMuted),
                const SizedBox(width: KnightSpacing.sm),
              ],
              // Bounded, so the segments share the width instead of overflowing.
              const Flexible(child: LanguageSelector()),
            ],
          ),
        ),
        const SizedBox(height: KnightSpacing.lg),
        KnightRing(
          size: 160,
          segments: [for (final t in RoutineType.values) RingSegment(progress: 1, color: tokens.routineColor(t))],
          center: Icon(Icons.shield_outlined, size: 40, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: KnightSpacing.xl),
        Semantics(
          header: true,
          child: Text(
            l.onboardingWelcomeTitle,
            textAlign: TextAlign.center,
            // The Latin brand wordmark in every language, so the tracking stays.
            style: theme.textTheme.headlineLarge?.copyWith(letterSpacing: 4),
          ),
        ),
        const SizedBox(height: KnightSpacing.sm),
        Text(
          l.tagline,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
        ),
        const SizedBox(height: KnightSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: KnightCard(
            chamfered: true,
            glow: true,
            child: Column(
              children: [
                Text(l.onboardingWelcomeOath, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                const SizedBox(height: KnightSpacing.md),
                Text(
                  l.onboardingWelcomeBody,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---- Step 2: routines ------------------------------------------------------

class _RoutinesStep extends StatelessWidget {
  const _RoutinesStep();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<OnboardingCubit>().state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(title: l.onboardingRoutinesTitle, subtitle: l.onboardingRoutinesSubtitle),
        for (final r in state.routines) ...[_RoutineCard(routine: r), const SizedBox(height: KnightSpacing.md)],
        if (!state.hasEnabledRoutine)
          Text(
            l.onboardingRoutinesHint,
            key: const Key('routines-hint'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({required this.routine});

  final Routine routine;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<OnboardingCubit>();
    final tokens = context.knight;
    final type = routine.type;
    final color = tokens.routineColor(type);
    final options = {...OnboardingCubit.intervalOptions(type), routine.intervalMinutes}.toList()..sort();
    return KnightCard(
      key: Key('routine-card-${type.name}'),
      glow: routine.enabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(type.icon, color: color),
              const SizedBox(width: KnightSpacing.md),
              Expanded(child: Text(type.label(l), style: Theme.of(context).textTheme.titleMedium)),
              Switch(
                key: Key('routine-switch-${type.name}'),
                value: routine.enabled,
                onChanged: (v) => cubit.setRoutineEnabled(type, enabled: v),
              ),
            ],
          ),
          const SizedBox(height: KnightSpacing.sm),
          Wrap(
            spacing: KnightSpacing.sm,
            runSpacing: KnightSpacing.sm,
            children: [
              for (final minutes in options)
                ChoiceChip(
                  key: Key('interval-${type.name}-$minutes'),
                  label: Text(l.onboardingIntervalChip(minutes)),
                  selected: routine.intervalMinutes == minutes,
                  onSelected: routine.enabled ? (_) => cubit.setInterval(type, minutes) : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- Step 3: work hours ----------------------------------------------------

class _WorkHoursStep extends StatelessWidget {
  const _WorkHoursStep();

  Future<void> _pick(BuildContext context, {required bool start}) async {
    final cubit = context.read<OnboardingCubit>();
    final minute = start ? cubit.state.startMinute : cubit.state.endMinute;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (minute ~/ 60) % 24, minute: minute % 60),
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (picked == null) return;
    final value = picked.hour * 60 + picked.minute;
    // 00:00 as an end time means "end of day".
    start ? cubit.setStart(value) : cubit.setEnd(value == 0 ? 1440 : value);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final cubit = context.read<OnboardingCubit>();
    final state = context.watch<OnboardingCubit>().state;
    final problem = state.workHoursProblem;
    final presetLabels = {
      WorkDaysPreset.sunThu: l.onboardingPresetSunThu,
      WorkDaysPreset.monFri: l.onboardingPresetMonFri,
      WorkDaysPreset.custom: l.onboardingPresetCustom,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(title: l.onboardingHoursTitle, subtitle: l.onboardingHoursSubtitle),
        Wrap(
          spacing: KnightSpacing.sm,
          runSpacing: KnightSpacing.sm,
          children: [
            for (final p in WorkDaysPreset.values)
              ChoiceChip(
                key: Key('preset-${p.name}'),
                label: Text(presetLabels[p]!),
                selected: state.preset == p,
                onSelected: (_) => cubit.setPreset(p),
              ),
          ],
        ),
        if (state.preset == WorkDaysPreset.custom) ...[
          const SizedBox(height: KnightSpacing.md),
          Wrap(
            spacing: KnightSpacing.sm,
            runSpacing: KnightSpacing.sm,
            children: [
              for (final d in weekdaysSundayFirst)
                FilterChip(
                  key: Key('day-$d'),
                  label: Text(weekdayName(locale, d, short: true)),
                  selected: state.days.contains(d),
                  onSelected: (_) => cubit.toggleDay(d),
                ),
            ],
          ),
        ],
        const SizedBox(height: KnightSpacing.xl),
        Row(
          children: [
            Expanded(
              child: _TimeButton(
                key: const Key('start-time'),
                label: l.onboardingStartTime,
                minute: state.startMinute,
                onTap: () => unawaited(_pick(context, start: true)),
              ),
            ),
            const SizedBox(width: KnightSpacing.md),
            Expanded(
              child: _TimeButton(
                key: const Key('end-time'),
                label: l.onboardingEndTime,
                minute: state.endMinute,
                onTap: () => unawaited(_pick(context, start: false)),
              ),
            ),
          ],
        ),
        const SizedBox(height: KnightSpacing.lg),
        if (problem == null)
          KnightCard(
            glow: true,
            child: Text(
              workScheduleSummary(l, locale, state.schedule),
              key: const Key('hours-summary'),
              style: theme.textTheme.titleMedium,
            ),
          )
        else
          Text(
            switch (problem) {
              WorkHoursProblem.noDays => l.onboardingNoDays,
              WorkHoursProblem.endNotAfterStart => l.onboardingEndAfterStart,
              WorkHoursProblem.tooShort => l.onboardingTooShort(WorkScheduleLimits.minWindowMinutes),
            },
            key: const Key('hours-error'),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
          ),
        const SizedBox(height: KnightSpacing.lg),
        Text(l.onboardingSplitShifts, style: theme.textTheme.bodySmall?.copyWith(color: context.knight.textMuted)),
      ],
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.label, required this.minute, required this.onTap, super.key});

  final String label;
  final int minute;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: KnightSpacing.md)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.labelMedium?.copyWith(color: context.knight.textMuted)),
          Text(formatMinuteOfDay(minute), style: theme.textTheme.titleLarge),
        ],
      ),
    );
  }
}

// ---- Step 4: oath ----------------------------------------------------------

class _OathStep extends StatelessWidget {
  const _OathStep();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: context.knight.textMuted);
    final finishFailed = context.select<OnboardingCubit, bool>((c) => c.state.finishFailed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(title: l.onboardingOathTitle, subtitle: l.onboardingOathBody),
        BlocBuilder<NotificationPermissionCubit, NotificationPermissionState>(
          builder: (context, permission) {
            if (permission.status == NotificationPermissionStatus.enabled) {
              return KnightCard(
                key: const Key('reminders-enabled'),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: context.knight.success),
                    const SizedBox(width: KnightSpacing.md),
                    Expanded(child: Text(l.onboardingRemindersEnabled, style: theme.textTheme.titleMedium)),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('enable-reminders'),
                    onPressed: () => unawaited(context.read<NotificationPermissionCubit>().request()),
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: Text(l.onboardingEnableReminders),
                  ),
                ),
                if (permission.requestDenied) ...[
                  const SizedBox(height: KnightSpacing.sm),
                  Text(l.onboardingRemindersBlocked, key: const Key('reminders-blocked'), style: muted),
                ],
              ],
            );
          },
        ),
        if (isDesktopPlatform(defaultTargetPlatform)) ...[
          const SizedBox(height: KnightSpacing.lg),
          KnightCard(
            key: const Key('launch-at-login'),
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              key: const Key('launch-at-login-switch'),
              title: Text(l.onboardingLaunchAtLoginTitle),
              subtitle: Text(l.onboardingLaunchAtLoginSubtitle),
              value: context.select<OnboardingCubit, bool>((c) => c.state.launchAtLogin),
              onChanged: (v) => context.read<OnboardingCubit>().setLaunchAtLogin(value: v),
            ),
          ),
        ],
        if (defaultTargetPlatform == TargetPlatform.android) ...[
          const SizedBox(height: KnightSpacing.lg),
          Text(l.onboardingBatteryNote, key: const Key('battery-note'), style: muted),
        ],
        if (finishFailed) ...[
          const SizedBox(height: KnightSpacing.lg),
          Text(
            l.onboardingFinishFailed,
            key: const Key('finish-failed'),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }
}
