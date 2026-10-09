import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:knight_rise/core/config/app_info.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';
import 'package:knight_rise/core/theme/widgets/knight_card.dart';
import 'package:knight_rise/features/device_health/presentation/device_health_cubit.dart';
import 'package:knight_rise/features/settings/presentation/locale_cubit.dart';
import 'package:knight_rise/features/settings/presentation/settings_cubit.dart';
import 'package:knight_rise/features/settings/presentation/settings_list_detail.dart';
import 'package:knight_rise/features/settings/presentation/theme_cubit.dart';
import 'package:knight_rise/features/settings/presentation/widgets/language_selector.dart';
import 'package:knight_rise/features/work_hours/presentation/work_format.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Settings hub. Needs a [ThemeCubit] and a [LocaleCubit] above it; the [SettingsCubit] and the
/// [DeviceHealthCubit] (for the Device health summary) are resolved from DI
/// unless given (tests).
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.cubit, this.healthCubit});

  final SettingsCubit? cubit;
  final DeviceHealthCubit? healthCubit;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final DeviceHealthCubit _health = widget.healthCubit ?? getIt<DeviceHealthCubit>();

  @override
  void initState() {
    super.initState();
    unawaited(_health.refresh());
  }

  @override
  void dispose() {
    if (widget.healthCubit == null) unawaited(_health.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provided = widget.cubit;
    final view = BlocProvider.value(value: _health, child: const _SettingsView());
    return provided != null
        ? BlocProvider.value(value: provided, child: view)
        : BlocProvider(create: (_) => getIt<SettingsCubit>(), child: view);
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final current = SettingsPaneScope.maybeOf(context)?.location;
    final selectedColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.12);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          if (!state.loaded) return const Center(child: CircularProgressIndicator());
          final cubit = context.read<SettingsCubit>();
          return ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(
              KnightSpacing.lg,
              KnightSpacing.sm,
              KnightSpacing.lg,
              KnightSpacing.xxl,
            ),
            children: [
              _Group(
                title: l.settingsAppearance,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(KnightSpacing.lg),
                    child: BlocBuilder<ThemeCubit, ThemeVariant>(
                      builder: (context, variant) => SegmentedButton<ThemeVariant>(
                        key: const Key('themeSelector'),
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(value: ThemeVariant.midnight, label: Text(l.themeMidnight)),
                          ButtonSegment(value: ThemeVariant.amoled, label: Text(l.themeAmoled)),
                        ],
                        selected: {variant},
                        onSelectionChanged: (s) => context.read<ThemeCubit>().setVariant(s.first),
                      ),
                    ),
                  ),
                  SwitchListTile(
                    key: const Key('hapticsSwitch'),
                    title: Text(l.settingsHaptics),
                    subtitle: Text(l.settingsHapticsSubtitle),
                    value: state.settings.hapticsEnabled,
                    onChanged: (v) => cubit.setHapticsEnabled(value: v),
                  ),
                ],
              ),
              _Group(
                title: l.language,
                children: const [
                  Padding(
                    key: Key('languageRow'),
                    padding: EdgeInsets.all(KnightSpacing.lg),
                    child: LanguageSelector(),
                  ),
                ],
              ),
              _Group(
                title: l.settingsPlanSection,
                children: [
                  ListTile(
                    key: const Key('routinesRow'),
                    title: Text(l.settingsRoutines),
                    selected: settingsPathSelected(current, '/settings/routines'),
                    selectedTileColor: selectedColor,
                    onTap: () => unawaited(openSettingsRoute(context, '/settings/routines')),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                  ListTile(
                    key: const Key('workHoursRow'),
                    title: Text(l.settingsWorkHours),
                    subtitle: Text(workScheduleSummary(l, locale, state.schedule)),
                    selected: settingsPathSelected(current, '/settings/work-hours'),
                    selectedTileColor: selectedColor,
                    onTap: () => unawaited(openSettingsRoute(context, '/settings/work-hours')),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              _Group(
                title: l.settingsQuestSection,
                children: [_StreakGoal(percent: state.settings.streakThresholdPercent)],
              ),
              _Group(
                title: l.settingsShield,
                children: [
                  SwitchListTile(
                    key: const Key('recoverSwitch'),
                    title: Text(l.settingsRecoverTitle),
                    subtitle: Text(l.settingsRecoverSubtitle),
                    value: state.settings.shieldRecoverOnExit,
                    onChanged: (v) => cubit.setShieldRecoverOnExit(value: v),
                  ),
                ],
              ),
              _Group(
                title: l.settingsSystemSection,
                children: [
                  BlocBuilder<DeviceHealthCubit, DeviceHealthState>(
                    builder: (context, health) {
                      final count = health.actionable.length;
                      return ListTile(
                        key: const Key('deviceHealthRow'),
                        title: Text(l.settingsDeviceHealth),
                        subtitle: health.loaded ? Text(count == 0 ? l.healthAllGood : l.healthIssues(count)) : null,
                        selected: settingsPathSelected(current, ReservedRoutes.deviceHealth),
                        selectedTileColor: selectedColor,
                        onTap: () async {
                          final healthCubit = context.read<DeviceHealthCubit>();
                          await openSettingsRoute(context, ReservedRoutes.deviceHealth);
                          unawaited(healthCubit.refresh());
                        },
                        trailing: const Icon(Icons.chevron_right),
                      );
                    },
                  ),
                ],
              ),
              _Group(
                title: l.aboutTitle,
                children: [
                  ListTile(title: Text(l.appTitle), subtitle: Text(l.tagline)),
                  ListTile(title: Text(l.aboutVersion(kAppVersion))),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Streak goal slider (50–100 % in 5 % steps). Drags update the label
/// locally; the value is saved once, when the drag ends.
class _StreakGoal extends StatefulWidget {
  const _StreakGoal({required this.percent});

  final int percent;

  @override
  State<_StreakGoal> createState() => _StreakGoalState();
}

class _StreakGoalState extends State<_StreakGoal> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final value = (_dragging ?? widget.percent.toDouble()).clamp(
      SettingsCubit.streakGoalMin.toDouble(),
      SettingsCubit.streakGoalMax.toDouble(),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        KnightSpacing.lg,
        KnightSpacing.md,
        KnightSpacing.lg,
        KnightSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.settingsStreakGoal(value.round()), style: text.titleMedium),
          Text(l.settingsStreakGoalSubtitle, style: text.bodySmall),
          Slider(
            key: const Key('streakGoalSlider'),
            value: value,
            min: SettingsCubit.streakGoalMin.toDouble(),
            max: SettingsCubit.streakGoalMax.toDouble(),
            divisions: (SettingsCubit.streakGoalMax - SettingsCubit.streakGoalMin) ~/ SettingsCubit.streakGoalStep,
            label: '${value.round()}%',
            onChanged: (v) => setState(() => _dragging = v),
            onChangeEnd: (v) {
              setState(() => _dragging = null);
              unawaited(context.read<SettingsCubit>().setStreakThreshold(v.round()));
            },
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: KnightSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(KnightSpacing.xs, KnightSpacing.sm, 0, KnightSpacing.sm),
            child: Text(title.toUpperCase(), style: text.labelSmall?.copyWith(color: context.knight.textMuted)),
          ),
          KnightCard(
            padding: EdgeInsets.zero,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}
