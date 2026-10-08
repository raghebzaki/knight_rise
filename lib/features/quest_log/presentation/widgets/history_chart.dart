import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';
import 'package:knight_rise/features/quest_log/domain/services/history_series.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Height of the plot including the x-axis label band.
const double kHistoryChartHeight = 220;

/// One-series daily completion bars (0–100 %) with the goal as a reference
/// line. Rest days are drawn in the same hue at low opacity and named in the
/// key and tooltip (never color alone); days without data have no bar.
///
/// Mark specs follow the dataviz rules: bars at most 24 px with a 4 px
/// rounded data end and a square base, hairline solid grid, recessive axes.
/// The canvas is excluded from semantics; [semanticsLabel] summarizes it and
/// the table view carries every value.
class HistoryChart extends StatelessWidget {
  const HistoryChart({
    required this.series,
    required this.color,
    required this.thresholdPercent,
    required this.semanticsLabel,
    super.key,
  });

  final HistorySeries series;

  /// The series color (the routine's token, or `secondary` for all).
  final Color color;
  final int thresholdPercent;
  final String semanticsLabel;

  /// Opacity of rest-day bars.
  static const restOpacity = 0.35;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = context.knight;
    final axisStyle = theme.textTheme.labelSmall?.copyWith(
      color: tokens.textMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final days = series.days;
    final weekly = series.range == HistoryRange.week;

    return Semantics(
      // Its own node, so the summary is read on its own rather than merged
      // into the card's title.
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: SizedBox(
          height: kHistoryChartHeight,
          child: Padding(
            // Room for the "100%" tick above the plot.
            padding: const EdgeInsets.only(top: KnightSpacing.sm),
            child: _Entered(
              builder: (context, motion) => LayoutBuilder(
                builder: (context, constraints) {
                  const leftAxis = 48.0;
                  final slot = (constraints.maxWidth - leftAxis) / days.length;
                  // Thin marks: at most 24 px, and never filling the slot.
                  final barWidth = math.min(24, math.max(2, slot * 0.6)).toDouble();
                  final radius = Radius.circular(math.min(4, barWidth / 2));

                  return BarChart(
                    BarChartData(
                      minY: 0,
                      maxY: 100,
                      alignment: BarChartAlignment.spaceAround,
                      barGroups: [
                        for (var i = 0; i < days.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                // Bars grow from the baseline on first show.
                                toY: motion.entered ? days[i].percent ?? 0 : 0,
                                width: barWidth,
                                color: days[i].kind == HistoryDayKind.rest
                                    ? color.withValues(alpha: restOpacity)
                                    : color,
                                borderRadius: BorderRadius.vertical(top: radius),
                              ),
                            ],
                          ),
                      ],
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        horizontalInterval: 50,
                        getDrawingHorizontalLine: (_) => FlLine(color: scheme.outline, strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      extraLinesData: ExtraLinesData(
                        horizontalLines: [
                          HorizontalLine(
                            y: thresholdPercent.toDouble(),
                            color: scheme.onSurfaceVariant,
                            strokeWidth: 1,
                            // Dashed on purpose: it is a target, not a gridline.
                            // Named in the key below, so no label collides with a bar.
                            dashArray: const [4, 4],
                          ),
                        ],
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(),
                        rightTitles: const AxisTitles(),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: leftAxis,
                            interval: 50,
                            getTitlesWidget: (value, meta) => SideTitleWidget(
                              meta: meta,
                              child: Text(l.historyPercent(value.round()), style: axisStyle),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (value, meta) {
                              final i = value.round();
                              // 30 days: label every 7th day, counted back from
                              // the newest so yesterday is always labeled.
                              if (i < 0 || i >= days.length || (!weekly && (days.length - 1 - i) % 7 != 0)) {
                                return const SizedBox.shrink();
                              }
                              final date = days[i].date;
                              final text = weekly
                                  ? DateFormat.E(locale).format(date)
                                  : DateFormat.MMMd(locale).format(date);
                              return SideTitleWidget(
                                meta: meta,
                                // Keeps the first and last labels inside the card.
                                fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                                child: Text(text, style: axisStyle),
                              );
                            },
                          ),
                        ),
                      ),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => scheme.surfaceContainerHigh,
                          tooltipBorder: BorderSide(color: scheme.outline),
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          maxContentWidth: 160,
                          tooltipPadding: const EdgeInsets.symmetric(
                            horizontal: KnightSpacing.md,
                            vertical: KnightSpacing.sm,
                          ),
                          getTooltipItem: (group, _, _, _) {
                            final day = days[group.x];
                            return BarTooltipItem(
                              '${DateFormat.MMMEd(locale).format(day.date)}\n',
                              theme.textTheme.labelSmall!.copyWith(color: tokens.textMuted),
                              children: [
                                TextSpan(
                                  text: historyDayStatus(l, day),
                                  style: theme.textTheme.labelMedium!.copyWith(color: scheme.onSurface),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    duration: motion.reduced ? Duration.zero : KnightMotion.ring,
                    curve: Curves.easeOutCubic,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Builds with `motion.entered` false for the first frame, then `true`, so the
/// chart animates its bars in. With reduced motion it is entered at once.
class _Entered extends StatefulWidget {
  const _Entered({required this.builder});

  final Widget Function(BuildContext context, ({bool entered, bool reduced}) motion) builder;

  @override
  State<_Entered> createState() => _EnteredState();
}

class _EnteredState extends State<_Entered> {
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entered = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return widget.builder(context, (entered: _entered || reduced, reduced: reduced));
  }
}

/// "75% · Goal met", "40% · Rest day", "Off", "No data".
String historyDayStatus(AppLocalizations l, HistoryDay day) {
  final percent = day.percent == null ? null : l.historyPercent(day.percent!.round());
  return switch (day.kind) {
    HistoryDayKind.noData => l.historyNoData,
    HistoryDayKind.off => l.historyOff,
    HistoryDayKind.rest => '$percent · ${l.historyKeyRest}',
    HistoryDayKind.work => '$percent · ${day.goalMet ? l.historyGoalMet : l.historyBelowGoal}',
  };
}
