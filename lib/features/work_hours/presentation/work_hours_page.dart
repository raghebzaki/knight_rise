import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';
import 'package:knight_rise/core/theme/widgets/knight_card.dart';
import 'package:knight_rise/core/widgets/confirm_discard.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:knight_rise/features/work_hours/domain/work_schedule_validation.dart';
import 'package:knight_rise/features/work_hours/domain/work_week.dart';
import 'package:knight_rise/features/work_hours/presentation/work_format.dart';
import 'package:knight_rise/features/work_hours/presentation/work_hours_cubit.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

enum _Preset { sunThu, monFri, custom }

/// Weekly work-hours editor (Sunday first). The cubit comes from DI unless
/// [cubit] is given (tests).
class WorkHoursPage extends StatelessWidget {
  const WorkHoursPage({super.key, this.cubit});

  final WorkHoursCubit? cubit;

  @override
  Widget build(BuildContext context) {
    final provided = cubit;
    return provided != null
        ? BlocProvider.value(value: provided, child: const _WorkHoursView())
        : BlocProvider(
            create: (_) {
              final created = getIt<WorkHoursCubit>();
              unawaited(created.load());
              return created;
            },
            child: const _WorkHoursView(),
          );
  }
}

class _WorkHoursView extends StatelessWidget {
  const _WorkHoursView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<WorkHoursCubit>();
    return BlocBuilder<WorkHoursCubit, WorkHoursState>(
      builder: (context, state) {
        return PopScope(
          canPop: !state.isDirty,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final discard = await confirmDiscard(
              context,
              title: l.workHoursDiscardTitle,
              body: l.workHoursDiscardBody,
              discardLabel: l.workHoursDiscard,
              keepLabel: l.workHoursKeepEditing,
            );
            if (discard && context.mounted) Navigator.of(context).pop();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(l.workHoursTitle),
              actions: [
                PopupMenuButton<_Preset>(
                  key: const Key('presetsMenu'),
                  tooltip: l.workHoursPresets,
                  icon: const Icon(Icons.tune),
                  onSelected: (p) => switch (p) {
                    _Preset.sunThu => cubit.applySunThu(),
                    _Preset.monFri => cubit.applyMonFri(),
                    _Preset.custom => null,
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: _Preset.sunThu, child: Text(l.workHoursPresetSunThu)),
                    PopupMenuItem(value: _Preset.monFri, child: Text(l.workHoursPresetMonFri)),
                    PopupMenuItem(value: _Preset.custom, child: Text(l.workHoursPresetCustom)),
                  ],
                ),
                IconButton(
                  key: const Key('copySunday'),
                  tooltip: l.workHoursCopySunday,
                  icon: const Icon(Icons.content_copy_outlined),
                  onPressed: state.loaded ? cubit.copySundayToWorkDays : null,
                ),
                TextButton(
                  key: const Key('saveButton'),
                  onPressed: state.canSave ? () => _save(context, cubit) : null,
                  child: Text(l.workHoursSave),
                ),
                const SizedBox(width: KnightSpacing.sm),
              ],
            ),
            body: !state.loaded
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      KnightSpacing.lg,
                      KnightSpacing.sm,
                      KnightSpacing.lg,
                      KnightSpacing.xxl,
                    ),
                    children: [for (final day in weekdaysSundayFirst) _DayCard(weekday: day, state: state)],
                  ),
          ),
        );
      },
    );
  }

  Future<void> _save(BuildContext context, WorkHoursCubit cubit) async {
    final saved = await cubit.save();
    if (saved && context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.weekday, required this.state});

  final int weekday;
  final WorkHoursState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final cubit = context.read<WorkHoursCubit>();
    final text = Theme.of(context).textTheme;
    final on = state.enabled.contains(weekday);
    final windows = state.windowsOf(weekday);
    final issues = state.issuesFor(weekday);
    final name = weekdayName(locale, weekday);

    return Padding(
      padding: const EdgeInsets.only(bottom: KnightSpacing.md),
      child: KnightCard(
        padding: const EdgeInsets.symmetric(vertical: KnightSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: Key('daySwitch$weekday'),
              title: Text(name, style: text.titleMedium),
              subtitle: on ? null : Text(l.workHoursDayOff),
              value: on,
              onChanged: (v) => cubit.setDayEnabled(weekday, enabled: v),
            ),
            if (on) ...[
              if (windows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KnightSpacing.lg),
                  child: Text(l.workHoursNoWindows, style: text.bodyMedium?.copyWith(color: context.knight.textMuted)),
                ),
              for (var i = 0; i < windows.length; i++)
                _WindowRow(weekday: weekday, index: i, window: windows[i], name: name),
              for (final issue in issues)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    KnightSpacing.lg,
                    KnightSpacing.xs,
                    KnightSpacing.lg,
                    0,
                  ),
                  child: Text(
                    _issueText(l, issue, windows),
                    key: Key('issue$weekday'),
                    style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KnightSpacing.sm),
                child: TextButton.icon(
                  key: Key('addWindow$weekday'),
                  onPressed: state.canAddWindow(weekday) ? () => cubit.addWindow(weekday) : null,
                  icon: const Icon(Icons.add),
                  label: Text(l.workHoursAddWindow),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _issueText(AppLocalizations l, WorkScheduleIssue issue, List<TimeWindow> windows) {
    final at = issue.windowIndex;
    final which = at == null ? '' : '${formatWindow(windows[at])}: ';
    return which +
        switch (issue.type) {
          WorkScheduleIssueType.endNotAfterStart => l.workHoursEndAfterStart,
          WorkScheduleIssueType.tooShort => l.workHoursIssueTooShort(WorkScheduleLimits.minWindowMinutes),
          WorkScheduleIssueType.overlap => l.workHoursIssueOverlap,
          WorkScheduleIssueType.tooManyWindows => l.workHoursIssueTooMany(WorkScheduleLimits.maxWindowsPerDay),
        };
  }
}

class _WindowRow extends StatelessWidget {
  const _WindowRow({required this.weekday, required this.index, required this.window, required this.name});

  final int weekday;
  final int index;
  final TimeWindow window;
  final String name;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<WorkHoursCubit>();
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('window$weekday-$index-${window.startMinute}-${window.endMinute}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => cubit.removeWindow(weekday, index),
      background: Container(
        color: scheme.error.withValues(alpha: 0.2),
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: KnightSpacing.lg),
        child: Icon(Icons.delete_outline, color: scheme.error),
      ),
      child: ListTile(
        key: Key('window$weekday-$index'),
        title: Text(formatWindow(window)),
        leading: const Icon(Icons.schedule),
        onTap: () => _edit(context, cubit),
        trailing: IconButton(
          key: Key('deleteWindow$weekday-$index'),
          tooltip: l.workHoursDeleteWindow,
          icon: const Icon(Icons.delete_outline),
          onPressed: () => cubit.removeWindow(weekday, index),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WorkHoursCubit cubit) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final start = await _pick(context, window.startMinute, l.workHoursPickStart);
    if (start == null || !context.mounted) return;
    final end = await _pick(context, window.endMinute % 1440, l.workHoursPickEnd);
    if (end == null) return;
    if (!cubit.updateWindow(weekday, index, start, end)) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.workHoursEndAfterStart)));
    }
  }

  Future<int?> _pick(BuildContext context, int minute, String help) async {
    final picked = await showTimePicker(
      context: context,
      helpText: help,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    return picked == null ? null : picked.hour * 60 + picked.minute;
  }
}
