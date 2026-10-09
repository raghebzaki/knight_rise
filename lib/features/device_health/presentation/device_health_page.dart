import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';
import 'package:knight_rise/core/theme/widgets/knight_card.dart';
import 'package:knight_rise/features/device_health/domain/device_health_report.dart';
import 'package:knight_rise/features/device_health/domain/health_issue.dart';
import 'package:knight_rise/features/device_health/domain/oem_guide.dart';
import 'package:knight_rise/features/device_health/presentation/device_health_cubit.dart';
import 'package:knight_rise/features/device_health/presentation/oem_guide_text.dart';
import 'package:knight_rise/features/settings/presentation/settings_list_detail.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Permission and battery status with fixes and per-maker guides. The
/// [DeviceHealthCubit] comes from DI unless [cubit] is given (tests).
class DeviceHealthPage extends StatefulWidget {
  const DeviceHealthPage({super.key, this.cubit});

  final DeviceHealthCubit? cubit;

  @override
  State<DeviceHealthPage> createState() => _DeviceHealthPageState();
}

class _DeviceHealthPageState extends State<DeviceHealthPage> {
  late final DeviceHealthCubit _cubit = widget.cubit ?? getIt<DeviceHealthCubit>();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_cubit.refresh()));
    unawaited(_cubit.refresh());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    if (widget.cubit == null) unawaited(_cubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.healthTitle),
          automaticallyImplyLeading: SettingsPaneScope.maybeOf(context) == null,
        ),
        body: BlocBuilder<DeviceHealthCubit, DeviceHealthState>(
          builder: (context, state) {
            final report = state.report;
            if (report == null) return const Center(child: CircularProgressIndicator());
            final android = report.platform == HealthPlatform.android;
            final ios = report.platform == HealthPlatform.ios;
            return ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(
                KnightSpacing.lg,
                KnightSpacing.sm,
                KnightSpacing.lg,
                KnightSpacing.xxl,
              ),
              children: [
                KnightCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _NotificationsRow(report: report, issue: state.issue(HealthKind.notifications)),
                      if (android) _PrecisionRow(state: state, report: report),
                      if (android) _BatteryRow(report: report, issue: state.issue(HealthKind.battery)),
                      if (ios) _BackgroundRefreshRow(report: report, issue: state.issue(HealthKind.backgroundRefresh)),
                    ],
                  ),
                ),
                if (android) ...[
                  const SizedBox(height: KnightSpacing.lg),
                  _OemGuideCard(guide: guideFor(report.manufacturer)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

Color _statusColor(BuildContext context, HealthIssue? issue) {
  final tokens = context.knight;
  return switch (issue?.severity) {
    null => tokens.success,
    HealthSeverity.error => Theme.of(context).colorScheme.error,
    HealthSeverity.warning => tokens.warning,
    HealthSeverity.info => tokens.textMuted,
  };
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.rowKey,
    required this.icon,
    required this.title,
    required this.status,
    required this.issue,
    this.onFix,
  });

  final Key rowKey;
  final IconData icon;
  final String title;
  final String status;
  final HealthIssue? issue;
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListTile(
      key: rowKey,
      leading: Icon(icon, color: _statusColor(context, issue)),
      title: Text(title),
      subtitle: Text(status),
      trailing: issue != null && onFix != null ? FilledButton(onPressed: onFix, child: Text(l.healthFix)) : null,
    );
  }
}

class _NotificationsRow extends StatelessWidget {
  const _NotificationsRow({required this.report, required this.issue});

  final DeviceHealthReport report;
  final HealthIssue? issue;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _StatusRow(
      rowKey: const Key('healthNotificationsRow'),
      icon: Icons.notifications_active_outlined,
      title: l.healthNotificationsTitle,
      status: report.notificationsEnabled ? l.healthNotificationsOn : l.healthNotificationsOff,
      issue: issue,
      onFix: () => context.read<DeviceHealthCubit>().fix(HealthKind.notifications),
    );
  }
}

class _PrecisionRow extends StatelessWidget {
  const _PrecisionRow({required this.state, required this.report});

  final DeviceHealthState state;
  final DeviceHealthReport report;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<DeviceHealthCubit>();
    final issue = state.issue(HealthKind.exactAlarms);
    final on = report.precisionTiming || state.awaitingExactAlarms;
    return ListTile(
      key: const Key('healthPrecisionRow'),
      leading: Icon(Icons.timer_outlined, color: _statusColor(context, issue)),
      title: Text(l.healthPrecisionTitle),
      subtitle: Text(issue != null ? l.healthPrecisionNeeded : l.healthPrecisionHelp),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (issue != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: KnightSpacing.sm),
              child: FilledButton(
                key: const Key('healthPrecisionFix'),
                onPressed: () => cubit.fix(HealthKind.exactAlarms),
                child: Text(l.healthFix),
              ),
            ),
          Switch(
            key: const Key('healthPrecisionSwitch'),
            value: on,
            onChanged: (v) => cubit.setPrecisionTiming(value: v),
          ),
        ],
      ),
    );
  }
}

class _BatteryRow extends StatelessWidget {
  const _BatteryRow({required this.report, required this.issue});

  final DeviceHealthReport report;
  final HealthIssue? issue;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ignored = report.batteryOptimizationIgnored;
    return _StatusRow(
      rowKey: const Key('healthBatteryRow'),
      icon: Icons.battery_charging_full_outlined,
      title: l.healthBatteryTitle,
      status: switch (ignored) {
        true => l.healthBatteryOk,
        false => l.healthBatteryOptimized,
        null => l.healthBatteryUnknown,
      },
      issue: issue,
      onFix: () => context.read<DeviceHealthCubit>().fix(HealthKind.battery),
    );
  }
}

class _BackgroundRefreshRow extends StatelessWidget {
  const _BackgroundRefreshRow({required this.report, required this.issue});

  final DeviceHealthReport report;
  final HealthIssue? issue;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _StatusRow(
      rowKey: const Key('healthBackgroundRefreshRow'),
      icon: Icons.sync_outlined,
      title: l.healthRefreshTitle,
      status: switch (report.backgroundRefresh) {
        BackgroundRefresh.denied => l.healthRefreshDenied,
        BackgroundRefresh.restricted => l.healthRefreshRestricted,
        _ => l.healthRefreshOn,
      },
      issue: issue,
      onFix: () => context.read<DeviceHealthCubit>().fix(HealthKind.backgroundRefresh),
    );
  }
}

class _OemGuideCard extends StatelessWidget {
  const _OemGuideCard({required this.guide});

  final OemGuide guide;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final guideText = oemGuideText(l, guide.maker);
    return KnightCard(
      key: const Key('healthOemGuide'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(guideText.title, style: text.titleLarge),
          const SizedBox(height: KnightSpacing.sm),
          Text(l.healthOemIntro, style: text.bodyMedium),
          const SizedBox(height: KnightSpacing.md),
          for (final (i, step) in guideText.steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: KnightSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 24, child: Text('${i + 1}.', style: text.bodyMedium)),
                  Expanded(child: Text(step, style: text.bodyMedium)),
                ],
              ),
            ),
          const SizedBox(height: KnightSpacing.xs),
          Text(l.healthMore, style: text.labelSmall?.copyWith(color: context.knight.textMuted)),
          const SizedBox(height: KnightSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: OutlinedButton(
              key: const Key('healthOpenSettings'),
              onPressed: () => context.read<DeviceHealthCubit>().openOemSettings(guide),
              child: Text(l.healthOpenSettings),
            ),
          ),
        ],
      ),
    );
  }
}
