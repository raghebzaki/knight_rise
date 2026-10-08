import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:knight_rise/core/feedback/haptics.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/widgets/knight_card.dart';
import 'package:knight_rise/features/cycle/presentation/widgets/countdown_text.dart';
import 'package:knight_rise/features/scheduler/domain/entities/cycle_snapshot.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:knight_rise/features/shield/presentation/shield_cubit.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Shortest and longest custom Shield, and the step between them.
const int kCustomShieldMinMinutes = 15;
const int kCustomShieldMaxMinutes = 180;
const int kCustomShieldStepMinutes = 15;

/// "Shield" button under the Next-up card; opens the preset sheet.
class ShieldEntry extends StatelessWidget {
  const ShieldEntry({required this.onDuty, super.key});

  /// "Until I turn it off" needs a work window, so it is hidden off duty.
  final bool onDuty;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton.icon(
        onPressed: () => _openSheet(context),
        icon: const Icon(Icons.shield_outlined),
        label: Text(l.shieldButton),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    final cubit = context.read<ShieldCubit>();
    final choice = await showModalBottomSheet<ShieldPreset>(
      context: context,
      showDragHandle: true,
      builder: (_) => _PresetSheet(onDuty: onDuty),
    );
    if (choice == null || !context.mounted) return;
    context.haptic(HapticKind.selection);
    if (choice == ShieldPreset.custom) {
      final minutes = await showDialog<int>(context: context, builder: (_) => const _CustomDurationDialog());
      if (minutes != null) await cubit.start(ShieldPreset.custom, custom: Duration(minutes: minutes));
      return;
    }
    await cubit.start(choice);
  }
}

class _PresetSheet extends StatelessWidget {
  const _PresetSheet({required this.onDuty});

  final bool onDuty;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    Widget tile(String label, IconData icon, ShieldPreset preset) =>
        ListTile(leading: Icon(icon), title: Text(label), onTap: () => Navigator.of(context).pop(preset));
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(KnightSpacing.lg, 0, KnightSpacing.lg, KnightSpacing.sm),
            child: Text(l.shieldSheetTitle, style: text.titleLarge),
          ),
          tile(l.shieldPresetFocus, Icons.center_focus_strong_outlined, ShieldPreset.min25),
          tile(l.shieldPresetMeeting, Icons.groups_outlined, ShieldPreset.min50),
          if (onDuty) tile(l.shieldPresetUntilOff, Icons.all_inclusive, ShieldPreset.untilOff),
          tile(l.shieldPresetCustom, Icons.tune, ShieldPreset.custom),
        ],
      ),
    );
  }
}

class _CustomDurationDialog extends StatefulWidget {
  const _CustomDurationDialog();

  @override
  State<_CustomDurationDialog> createState() => _CustomDurationDialogState();
}

class _CustomDurationDialogState extends State<_CustomDurationDialog> {
  int _minutes = 30;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(l.shieldCustomTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.shieldCustomMinutes(_minutes), style: text.headlineSmall),
          Slider(
            value: _minutes.toDouble(),
            min: kCustomShieldMinMinutes.toDouble(),
            max: kCustomShieldMaxMinutes.toDouble(),
            divisions: (kCustomShieldMaxMinutes - kCustomShieldMinMinutes) ~/ kCustomShieldStepMinutes,
            label: l.shieldCustomMinutes(_minutes),
            onChanged: (v) => setState(() => _minutes = v.round()),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.overrideCancel)),
        FilledButton(onPressed: () => Navigator.of(context).pop(_minutes), child: Text(l.shieldCustomStart)),
      ],
    );
  }
}

/// Active Shield: countdown, optional recovery hint, +15 min and End.
class ShieldBanner extends StatelessWidget {
  const ShieldBanner({required this.snapshot, required this.shield, super.key});

  final CycleSnapshot snapshot;
  final ShieldSession shield;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final cubit = context.read<ShieldCubit>();
    final end = shield.effectiveEnd;
    // Same wall-clock formatting as the rest of the dashboard.
    final format = DateFormat.Hm(Localizations.localeOf(context).toLanguageTag());
    final recovery = snapshot.nextRecovery;
    return KnightCard(
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: KnightSpacing.md),
              Expanded(child: Text(l.shieldActive, style: text.titleLarge)),
              CountdownText(target: end, style: text.displaySmall?.copyWith(fontSize: 28)),
            ],
          ),
          if (recovery != null) ...[
            const SizedBox(height: KnightSpacing.xs),
            Text(l.shieldRecoveryAt(format.format(recovery.fireAt)), style: text.bodySmall),
          ],
          const SizedBox(height: KnightSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  context.haptic(HapticKind.light);
                  unawaited(cubit.extend());
                },
                child: Text(l.shieldExtend),
              ),
              const SizedBox(width: KnightSpacing.sm),
              FilledButton(
                onPressed: () {
                  context.haptic(HapticKind.success);
                  unawaited(cubit.end());
                },
                child: Text(l.shieldEnd),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Whether the day-override chips apply: today is a work day (on duty now or
/// still to start today) or already carries an override.
bool showOverrideChips(CycleSnapshot s) {
  if (s.onDuty || s.todayOverride != null) return true;
  final next = s.nextWorkStart;
  final now = s.computedAt;
  return next != null && next.year == now.year && next.month == now.month && next.day == now.day;
}

/// "+1h", "+2h", "+30m", "+1h 30m".
String formatExtension(int minutes) {
  if (minutes < 60) return '+${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '+${h}h' : '+${h}h ${m}m';
}

/// Compact row of today's overrides: Day off, Working late.
class OverrideChips extends StatelessWidget {
  const OverrideChips({required this.dayOverride, super.key});

  final DayOverride? dayOverride;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<ShieldCubit>();
    final off = dayOverride?.kind == DayOverrideKind.off;
    final extra = dayOverride?.kind == DayOverrideKind.extend ? (dayOverride?.extendMinutes ?? 0) : 0;
    const clearIcon = Icon(Icons.close, size: 18);
    return Wrap(
      spacing: KnightSpacing.sm,
      runSpacing: KnightSpacing.sm,
      children: [
        InputChip(
          avatar: const Icon(Icons.beach_access_outlined, size: 18),
          label: Text(l.overrideDayOff),
          selected: off,
          showCheckmark: false,
          onPressed: off ? null : () => _confirmDayOff(context, cubit),
          onDeleted: off ? cubit.clearToday : null,
          deleteIcon: clearIcon,
          deleteButtonTooltipMessage: l.overrideClear,
        ),
        InputChip(
          avatar: const Icon(Icons.more_time, size: 18),
          label: Text(extra > 0 ? l.overrideWorkLate(formatExtension(extra)) : l.overrideWorkLateAdd),
          selected: extra > 0,
          showCheckmark: false,
          onPressed: extra >= kMaxExtendMinutes ? null : cubit.workLateToday,
          onDeleted: extra > 0 ? cubit.clearToday : null,
          deleteIcon: clearIcon,
          deleteButtonTooltipMessage: l.overrideClear,
        ),
      ],
    );
  }

  /// Day off silences the whole day, so it asks first.
  Future<void> _confirmDayOff(BuildContext context, ShieldCubit cubit) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.overrideDayOffTitle),
        content: Text(l.overrideDayOffBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l.overrideCancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l.overrideDayOff)),
        ],
      ),
    );
    if (ok ?? false) await cubit.dayOffToday();
  }
}
