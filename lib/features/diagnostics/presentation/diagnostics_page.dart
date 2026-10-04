import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';
import 'package:knight_rise/core/theme/widgets/knight_card.dart';
import 'package:knight_rise/features/cycle/presentation/widgets/routine_presentation.dart';
import 'package:knight_rise/features/diagnostics/presentation/diagnostics_cubit.dart';
import 'package:knight_rise/features/notifications/domain/pending_reminder.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Dev-flavor debug screen: OS status, pending notifications, the reconcile
/// audit log and manual actions. Plain English on purpose (not localized).
class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({super.key, this.cubit});

  /// Injected in tests; resolved from DI otherwise.
  final DiagnosticsCubit? cubit;

  @override
  Widget build(BuildContext context) {
    final provided = cubit;
    return provided != null
        ? BlocProvider.value(value: provided, child: const DiagnosticsView())
        : BlocProvider(create: (_) => getIt<DiagnosticsCubit>()..unawaitedStart(), child: const DiagnosticsView());
  }
}

class DiagnosticsView extends StatelessWidget {
  const DiagnosticsView({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DiagnosticsCubit>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('DIAGNOSTICS'),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: cubit.refresh),
          const SizedBox(width: KnightSpacing.sm),
        ],
      ),
      body: BlocBuilder<DiagnosticsCubit, DiagnosticsState>(
        builder: (context, state) {
          if (!state.loaded) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.fromLTRB(KnightSpacing.lg, KnightSpacing.sm, KnightSpacing.lg, KnightSpacing.xxl),
            children: [
              if (state.error case final error?) ...[
                Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: KnightSpacing.lg),
              ],
              _Section(
                title: 'Status',
                child: _StatusSection(state: state),
              ),
              _Section(
                title: 'Actions',
                child: _ActionsSection(state: state),
              ),
              _Section(
                title: 'Pending notifications (${state.pending.length})',
                child: _PendingSection(state: state),
              ),
              _Section(
                title: 'Recent reconcile runs',
                child: _RunsSection(state: state),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: KnightSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: KnightSpacing.sm),
        KnightCard(child: child),
      ],
    ),
  );
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({required this.state});

  final DiagnosticsState state;

  @override
  Widget build(BuildContext context) {
    final tokens = context.knight;
    final error = Theme.of(context).colorScheme.error;
    final zonesMatch = state.settingsTimezoneId == state.deviceTimezoneId;
    return Column(
      children: [
        _Row('Timezone (settings)', state.settingsTimezoneId ?? 'not set'),
        _Row('Timezone (device)', state.deviceTimezoneId ?? 'unknown', color: zonesMatch ? null : tokens.warning),
        _Row(
          'Notifications enabled',
          state.notificationsEnabled ? 'yes' : 'no',
          color: state.notificationsEnabled ? tokens.success : error,
        ),
        _Row('Exact alarms allowed', state.canScheduleExact ? 'yes' : 'no'),
        _Row('Precision timing (setting)', state.precisionTiming ? 'on' : 'off'),
        _Row('Pending notifications', '${state.pending.length}'),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KnightSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: text.bodyMedium)),
          const SizedBox(width: KnightSpacing.md),
          Flexible(
            child: Text(
              value,
              style: text.labelLarge?.copyWith(color: color),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionsSection extends StatelessWidget {
  const _ActionsSection({required this.state});

  final DiagnosticsState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DiagnosticsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(onPressed: state.busy ? null : cubit.reconcileNow, child: const Text('Reconcile now')),
        const SizedBox(height: KnightSpacing.sm),
        OutlinedButton(
          onPressed: state.busy ? null : cubit.scheduleTest,
          child: const Text('Test notification in 1 min'),
        ),
      ],
    );
  }
}

class _PendingSection extends StatelessWidget {
  const _PendingSection({required this.state});

  final DiagnosticsState state;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (state.pending.isEmpty) return Text('Nothing pending.', style: text.bodyMedium);
    final cubit = context.read<DiagnosticsCubit>();
    final tokens = context.knight;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        for (final PendingReminder p in state.pending)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: KnightSpacing.xs),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    p.payload == null ? '--' : DateFormat('EEE HH:mm', locale).format(cubit.toLocal(p.payload!.fireAt)),
                    style: text.labelLarge,
                  ),
                ),
                for (final t in sortedTypes(p.payload?.types ?? const <RoutineType>{}))
                  Padding(
                    padding: const EdgeInsets.only(right: KnightSpacing.xs),
                    child: Icon(t.icon, size: 16, color: tokens.routineColor(t)),
                  ),
                Expanded(
                  child: Text(
                    p.payload == null
                        ? 'unknown payload'
                        : sortedTypes(p.payload!.types).map((t) => t.label(l)).join(' + '),
                    style: text.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('#${p.id}', style: text.bodySmall),
              ],
            ),
          ),
      ],
    );
  }

  static List<RoutineType> sortedTypes(Set<RoutineType> types) =>
      types.toList()..sort((a, b) => a.index.compareTo(b.index));
}

class _RunsSection extends StatelessWidget {
  const _RunsSection({required this.state});

  final DiagnosticsState state;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (state.runs.isEmpty) return Text('No runs recorded.', style: text.bodyMedium);
    final cubit = context.read<DiagnosticsCubit>();
    final errorColor = Theme.of(context).colorScheme.error;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Column(
      children: [
        for (final ReconcileRun r in state.runs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: KnightSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${DateFormat('EEE HH:mm:ss', locale).format(cubit.toLocal(r.at))}  ${r.trigger.name}',
                        style: text.labelLarge,
                      ),
                    ),
                    Text('plan ${r.planned} / +${r.added} / -${r.cancelled}', style: text.bodySmall),
                  ],
                ),
                if (r.error case final error?) Text(error, style: text.bodySmall?.copyWith(color: errorColor)),
              ],
            ),
          ),
      ],
    );
  }
}
