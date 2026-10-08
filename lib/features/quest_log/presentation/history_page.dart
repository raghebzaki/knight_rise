import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';
import 'package:knight_rise/core/theme/widgets/knight_card.dart';
import 'package:knight_rise/features/cycle/presentation/widgets/routine_presentation.dart';
import 'package:knight_rise/features/quest_log/domain/services/history_series.dart';
import 'package:knight_rise/features/quest_log/presentation/history_cubit.dart';
import 'package:knight_rise/features/quest_log/presentation/quest_log_page.dart' show formatFocusMinutes;
import 'package:knight_rise/features/quest_log/presentation/widgets/history_chart.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// History tab: one filter row (range + routine), the daily completion chart
/// (or its table twin), and headline stats for the same slice.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, this.cubitFactory});

  /// Builds the page's [HistoryCubit]; the DI container by default.
  final HistoryCubit Function()? cubitFactory;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late final HistoryCubit _cubit = (widget.cubitFactory ?? getIt.get<HistoryCubit>)()..start();
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
        appBar: AppBar(title: Text(l.historyTitle.toUpperCase(), style: Theme.of(context).textTheme.headlineSmall)),
        body: BlocBuilder<HistoryCubit, HistoryState>(
          builder: (context, state) => switch (state.status) {
            HistoryStatus.ready => _HistoryBody(state: state),
            HistoryStatus.failure => Center(child: Text(state.error ?? '')),
            HistoryStatus.loading => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }
}

/// The routine's color token, or `secondary` for all routines together
/// (distinct from the three routine hues; validated ≥ 3:1 on both surfaces).
Color historySeriesColor(BuildContext context, RoutineType? routine) =>
    routine == null ? Theme.of(context).colorScheme.secondary : context.knight.routineColor(routine);

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({required this.state});

  final HistoryState state;

  @override
  Widget build(BuildContext context) {
    final series = state.series;
    return ListView(
      padding: const EdgeInsets.fromLTRB(KnightSpacing.lg, KnightSpacing.sm, KnightSpacing.lg, KnightSpacing.xxl),
      children: [
        _Filters(state: state),
        const SizedBox(height: KnightSpacing.lg),
        if (series.isEmpty)
          const _EmptyHistory()
        else ...[
          _ChartCard(state: state, series: series),
          const SizedBox(height: KnightSpacing.lg),
          _StatTiles(stats: series.stats),
        ],
      ],
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.state});

  final HistoryState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<HistoryCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<HistoryRange>(
          segments: [
            ButtonSegment(value: HistoryRange.week, label: Text(l.historyRangeWeek)),
            ButtonSegment(value: HistoryRange.month, label: Text(l.historyRangeMonth)),
          ],
          selected: {state.range},
          showSelectedIcon: false,
          onSelectionChanged: (s) => cubit.setRange(s.single),
        ),
        const SizedBox(height: KnightSpacing.sm),
        // Wraps rather than scrolls, so every filter stays visible.
        Wrap(
          spacing: KnightSpacing.sm,
          runSpacing: KnightSpacing.sm,
          children: [
            for (final routine in <RoutineType?>[null, ...RoutineType.values])
              ChoiceChip(
                key: Key('history-filter-${routine?.name ?? 'all'}'),
                avatar: routine == null ? null : Icon(routine.icon, size: 18),
                label: Text(routine?.label(l) ?? l.historyAll),
                selected: state.routine == routine,
                onSelected: (_) => cubit.setRoutine(routine),
              ),
          ],
        ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.state, required this.series});

  final HistoryState state;
  final HistorySeries series;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final tokens = context.knight;
    final color = historySeriesColor(context, series.routine);
    final subject = series.routine?.label(l) ?? l.historyAll;
    final stats = series.stats;
    final summary = stats.completionRate == null
        ? l.historySummaryNoWork(subject, series.range.days)
        : l.historySummary(subject, series.range.days, stats.completionRate!.round(), stats.goalDays, stats.workDays);

    return KnightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.historyChartTitle, style: text.titleLarge),
                    Text(subject, style: text.bodySmall?.copyWith(color: tokens.textMuted)),
                  ],
                ),
              ),
              IconButton(
                key: const Key('history-table-toggle'),
                tooltip: state.showTable ? l.historyShowChart : l.historyShowTable,
                icon: Icon(state.showTable ? Icons.bar_chart : Icons.table_rows_outlined),
                onPressed: context.read<HistoryCubit>().toggleTable,
              ),
            ],
          ),
          const SizedBox(height: KnightSpacing.md),
          if (state.showTable)
            _HistoryTable(series: series)
          else ...[
            HistoryChart(
              series: series,
              color: color,
              thresholdPercent: state.thresholdPercent,
              semanticsLabel: summary,
            ),
            const SizedBox(height: KnightSpacing.sm),
            _Key(color: color, thresholdPercent: state.thresholdPercent),
          ],
        ],
      ),
    );
  }
}

/// Names what the two bar tones and the dashed goal line mean (identity is
/// never color alone).
class _Key extends StatelessWidget {
  const _Key({required this.color, required this.thresholdPercent});

  final Color color;
  final int thresholdPercent;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: context.knight.textMuted);
    Widget swatch(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: KnightSpacing.xs),
        Text(label, style: style),
      ],
    );
    final dash = Theme.of(context).colorScheme.onSurfaceVariant;
    return ExcludeSemantics(
      child: Wrap(
        spacing: KnightSpacing.lg,
        runSpacing: KnightSpacing.xs,
        children: [
          swatch(color, l.historyKeyWork),
          swatch(color.withValues(alpha: HistoryChart.restOpacity), l.historyKeyRest),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) ...[
                Container(width: 4, height: 1, color: dash),
                if (i < 2) const SizedBox(width: 3),
              ],
              const SizedBox(width: KnightSpacing.xs),
              Text(l.historyGoalLine(thresholdPercent), style: style),
            ],
          ),
        ],
      ),
    );
  }
}

/// The chart's table twin: every value, newest first.
class _HistoryTable extends StatelessWidget {
  const _HistoryTable({required this.series});

  final HistorySeries series;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final text = Theme.of(context).textTheme;
    final tabular = text.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Column(
      key: const Key('history-table'),
      children: [
        for (final day in series.days.reversed)
          MergeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: KnightSpacing.xs),
              child: Row(
                children: [
                  Expanded(child: Text(DateFormat.MMMEd(locale).format(day.date), style: tabular)),
                  Text(historyDayStatus(l, day), style: tabular),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _StatTiles extends StatelessWidget {
  const _StatTiles({required this.stats});

  final HistoryStats stats;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final rate = stats.completionRate;
    final water = stats.averageWaterMl;
    final tiles = [
      _StatTile(
        key: const Key('stat-completion'),
        label: l.statCompletion,
        value: rate == null ? l.statNone : l.historyPercent(rate.round()),
        detail: l.statCompletionDetail(stats.goalDays, stats.workDays),
      ),
      _StatTile(
        key: const Key('stat-focus'),
        label: l.statFocus,
        value: formatFocusMinutes(l, stats.focusMinutes),
        detail: l.statInWindow,
      ),
      _StatTile(
        key: const Key('stat-water'),
        label: l.statWater,
        value: water == null ? l.statNone : l.statWaterValue(NumberFormat.decimalPattern(locale).format(water)),
        detail: l.statPerWorkDay,
      ),
      _StatTile(
        key: const Key('stat-streak'),
        label: l.statBestStreak,
        value: l.statDays(stats.bestStreak),
        detail: l.statInWindow,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - KnightSpacing.md) / 2;
        return Wrap(
          spacing: KnightSpacing.md,
          runSpacing: KnightSpacing.md,
          children: [for (final t in tiles) SizedBox(width: width, child: t)],
        );
      },
    );
  }
}

/// Stat tile: label, value (proportional figures), one line of context.
class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.detail, super.key});

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = context.knight.textMuted;
    return KnightCard(
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: text.labelMedium?.copyWith(color: muted)),
            const SizedBox(height: KnightSpacing.xs),
            // Body sans (Inter) semibold with proportional figures, not a display face.
            Text(value, style: text.titleMedium?.copyWith(fontSize: 22, height: 28 / 22)),
            Text(detail, style: text.bodySmall?.copyWith(color: muted)),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return KnightCard(
      key: const Key('history-empty'),
      padding: const EdgeInsets.all(KnightSpacing.xl),
      child: Column(
        children: [
          Icon(Icons.insights_outlined, size: 40, color: context.knight.textMuted),
          const SizedBox(height: KnightSpacing.md),
          Text(l.historyEmpty, style: text.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
