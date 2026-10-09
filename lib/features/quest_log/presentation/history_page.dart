import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/layout/adaptive_columns.dart';
import 'package:knight_rise/core/layout/window_size.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';
import 'package:knight_rise/core/theme/text_scale.dart';
import 'package:knight_rise/core/theme/widgets/knight_card.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/core/widgets/knight_error_view.dart';
import 'package:knight_rise/features/cycle/presentation/widgets/routine_presentation.dart';
import 'package:knight_rise/features/quest_log/domain/entities/daily_summary.dart';
import 'package:knight_rise/features/quest_log/domain/services/history_series.dart';
import 'package:knight_rise/features/quest_log/presentation/history_cubit.dart';
import 'package:knight_rise/features/quest_log/presentation/quest_log_page.dart'
    show formatFocusMinutes, routineMeasureText;
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
            HistoryStatus.failure => KnightErrorView(details: state.error, onRetry: _cubit.start),
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

/// The History content; on multi-pane windows also owns which day the
/// detail pane shows (a hover preview over a click-to-pin selection).
class _HistoryBody extends StatefulWidget {
  const _HistoryBody({required this.state});

  final HistoryState state;

  @override
  State<_HistoryBody> createState() => _HistoryBodyState();
}

class _HistoryBodyState extends State<_HistoryBody> {
  /// Day shown while the pointer is over a bar; wins over [_pinned].
  DateTime? _preview;

  /// Day kept in the pane until another is clicked or it is released.
  DateTime? _pinned;

  @override
  void didUpdateWidget(_HistoryBody old) {
    super.didUpdateWidget(old);
    // A different slice makes the pinned day meaningless.
    if (old.state.range != widget.state.range || old.state.routine != widget.state.routine) {
      _preview = null;
      _pinned = null;
    }
  }

  void _setPreview(DateTime? day) {
    if (day != _preview) setState(() => _preview = day);
  }

  void _togglePin(DateTime day) => setState(() => _pinned = _pinned == day ? null : day);

  void _unpin() => setState(() => _pinned = null);

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final series = state.series;
    final multi = context.isMultiPane;
    const padding = EdgeInsetsDirectional.fromSTEB(
      KnightSpacing.lg,
      KnightSpacing.sm,
      KnightSpacing.lg,
      KnightSpacing.xxl,
    );
    final days = {for (final d in series.days) d.date: d};
    final pinned = days.containsKey(_pinned) ? _pinned : null;
    final preview = days.containsKey(_preview) ? _preview : null;
    final content = ListView(
      padding: multi ? padding.copyWith(end: 0) : padding,
      children: [
        _Filters(state: state),
        const SizedBox(height: KnightSpacing.lg),
        if (series.isEmpty)
          const _EmptyHistory()
        else ...[
          _ChartCard(
            state: state,
            series: series,
            selected: multi ? (preview ?? pinned) : null,
            onPreview: multi ? _setPreview : null,
            onPin: multi ? _togglePin : null,
          ),
          const SizedBox(height: KnightSpacing.lg),
          _StatTiles(stats: series.stats),
        ],
      ],
    );
    if (!multi) return content;

    // The default day: the latest work day of the window.
    final fallback = series.days.where((d) => d.kind == HistoryDayKind.work).lastOrNull?.date;
    final shown = preview ?? pinned ?? fallback;
    return AdaptiveTwoColumn(
      startFlex: 3,
      endFlex: 2,
      start: content,
      end: ListView(
        padding: padding.copyWith(start: 0),
        children: [
          _DayDetailPane(
            day: shown == null ? null : days[shown],
            summary: shown == null ? null : state.summaryOn(shown),
            pinned: shown != null && shown == pinned,
            onUnpin: _unpin,
          ),
        ],
      ),
    );
  }
}

/// The focused day: date, status for the current filter, and what each
/// routine, the water and the shield time added up to that day.
class _DayDetailPane extends StatelessWidget {
  const _DayDetailPane({required this.day, required this.summary, required this.pinned, required this.onUnpin});

  /// The day's bar, or null when there is nothing to show.
  final HistoryDay? day;

  /// The finalized summary behind [day], null when there is no data.
  final DailySummary? summary;
  final bool pinned;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final text = Theme.of(context).textTheme;
    final muted = context.knight.textMuted;
    final day = this.day;
    final summary = this.summary;
    return KnightCard(
      key: const Key('history-day-pane'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(l.historyDayDetailTitle, style: text.titleLarge)),
              if (pinned) ...[
                Icon(Icons.push_pin, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: KnightSpacing.xs),
                Text(l.historyDayPinned, key: const Key('history-pane-pinned'), style: text.labelMedium),
                IconButton(
                  key: const Key('history-pane-unpin'),
                  tooltip: l.historyDayUnpin,
                  icon: const Icon(Icons.close),
                  onPressed: onUnpin,
                ),
              ],
            ],
          ),
          const SizedBox(height: KnightSpacing.md),
          if (day == null)
            Text(l.historyDayPlaceholder, key: const Key('history-pane-placeholder'), style: text.bodyMedium)
          else ...[
            Text(
              DateFormat.yMMMMEEEEd(locale).format(day.date),
              key: const Key('history-pane-date'),
              style: text.titleMedium,
            ),
            Text(
              historyDayStatus(l, day),
              key: const Key('history-pane-status'),
              style: text.bodyMedium?.copyWith(color: muted),
            ),
            if (summary != null) ...[
              const SizedBox(height: KnightSpacing.lg),
              Text(l.historyDayRoutines, style: text.labelMedium?.copyWith(color: muted)),
              const SizedBox(height: KnightSpacing.xs),
              for (final r in summary.routines)
                _PaneRow(
                  icon: r.type.icon,
                  label: r.type.label(l),
                  value: r.enabled ? routineMeasureText(l, summary, r) : l.historyOff,
                ),
              const Divider(height: KnightSpacing.xl),
              _PaneRow(
                icon: Icons.shield_outlined,
                label: l.statFocus,
                value: formatFocusMinutes(l, summary.focusMinutes),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Label and value on one line; stacked at large text so neither is clipped.
class _PaneRow extends StatelessWidget {
  const _PaneRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tabular = text.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final name = Row(
      children: [
        Icon(icon, size: 18, color: context.knight.textMuted),
        const SizedBox(width: KnightSpacing.sm),
        Expanded(child: Text(label, style: text.bodyMedium)),
      ],
    );
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: KnightSpacing.xs),
        child: context.isLargeText
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  name,
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 18 + KnightSpacing.sm),
                    child: Text(value, style: tabular),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: name),
                  const SizedBox(width: KnightSpacing.sm),
                  Text(value, style: tabular),
                ],
              ),
      ),
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
  const _ChartCard({required this.state, required this.series, this.selected, this.onPreview, this.onPin});

  final HistoryState state;
  final HistorySeries series;

  /// The day shown in the detail pane (multi-pane only), highlighted in the table.
  final DateTime? selected;

  /// Hover over a bar (null when it leaves); set only with a detail pane.
  final ValueChanged<DateTime?>? onPreview;

  /// Click on a bar or table row; set only with a detail pane.
  final ValueChanged<DateTime>? onPin;

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
            _HistoryTable(series: series, selected: selected, onPin: onPin)
          else ...[
            HistoryChart(
              series: series,
              color: color,
              thresholdPercent: state.thresholdPercent,
              semanticsLabel: summary,
              // The detail pane replaces the tooltip.
              showTooltip: onPin == null,
              onDayHover: onPreview == null ? null : (i) => onPreview!(i == null ? null : series.days[i].date),
              onDayTap: onPin == null ? null : (i) => onPin!(series.days[i].date),
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

/// The chart's table twin: every value, newest first. With [onPin], rows are
/// focusable buttons that pin their day in the detail pane.
class _HistoryTable extends StatelessWidget {
  const _HistoryTable({required this.series, this.selected, this.onPin});

  final HistorySeries series;
  final DateTime? selected;
  final ValueChanged<DateTime>? onPin;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final text = Theme.of(context).textTheme;
    final tabular = text.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final highlight = Theme.of(context).colorScheme.primary.withValues(alpha: 0.12);
    return Column(
      key: const Key('history-table'),
      children: [
        for (final day in series.days.reversed)
          MergeSemantics(
            child: Semantics(
              selected: onPin == null ? null : day.date == selected,
              child: InkWell(
                key: Key('history-row-${dateKey(day.date)}'),
                onTap: onPin == null ? null : () => onPin!(day.date),
                borderRadius: BorderRadius.circular(KnightRadius.sm),
                child: Container(
                  decoration: BoxDecoration(
                    color: day.date == selected ? highlight : null,
                    borderRadius: BorderRadius.circular(KnightRadius.sm),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: KnightSpacing.xs, horizontal: KnightSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(child: Text(DateFormat.MMMEd(locale).format(day.date), style: tabular)),
                      Text(historyDayStatus(l, day), style: tabular),
                    ],
                  ),
                ),
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
        value: water == null ? l.statNone : l.statWaterValue(water),
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
