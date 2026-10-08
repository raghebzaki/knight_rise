import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/features/quest_log/domain/entities/daily_summary.dart';
import 'package:knight_rise/features/quest_log/domain/services/streak_calculator.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:meta/meta.dart';

/// History chart windows: the last 7 or 30 finalized days (today is shown
/// live on the Quest Log, not here).
enum HistoryRange {
  week(7),
  month(30);

  HistoryRange(this.days);

  final int days;
}

enum HistoryDayKind {
  /// No summary: before history started, or not finalized yet.
  noData,

  /// No work window or a "day off": shown dimmed, never counted.
  rest,

  /// A work day on which the filtered routine (or every routine) was off.
  off,

  /// A work day that counts.
  work,
}

/// One bar of the history chart.
@immutable
class HistoryDay {
  const HistoryDay({required this.date, required this.kind, this.percent, this.goalMet = false});

  /// Local date, date-only.
  final DateTime date;
  final HistoryDayKind kind;

  /// Completion 0..100 for [HistoryDayKind.work] and [HistoryDayKind.rest]
  /// days, null otherwise.
  final double? percent;

  /// True when the day reached its streak threshold (work days only).
  final bool goalMet;

  @override
  bool operator ==(Object other) =>
      other is HistoryDay &&
      other.date == date &&
      other.kind == kind &&
      other.percent == percent &&
      other.goalMet == goalMet;

  @override
  int get hashCode => Object.hash(date, kind, percent, goalMet);

  @override
  String toString() => 'HistoryDay(${dateKey(date)}, $kind, $percent, met: $goalMet)';
}

/// Headline numbers for a window.
@immutable
class HistoryStats {
  const HistoryStats({
    required this.workDays,
    required this.goalDays,
    required this.focusMinutes,
    required this.bestStreak,
    this.completionRate,
    this.averageWaterMl,
  });

  /// Work days in the window that count for the filter.
  final int workDays;

  /// Of those, days that reached the goal.
  final int goalDays;

  /// Mean completion over [workDays], 0..100; null when there are none.
  final double? completionRate;

  /// Shield minutes over every finalized day in the window.
  final int focusMinutes;

  /// Mean water per finalized work day; null when there are none.
  final int? averageWaterMl;

  /// Longest streak inside the window.
  final int bestStreak;

  @override
  bool operator ==(Object other) =>
      other is HistoryStats &&
      other.workDays == workDays &&
      other.goalDays == goalDays &&
      other.completionRate == completionRate &&
      other.focusMinutes == focusMinutes &&
      other.averageWaterMl == averageWaterMl &&
      other.bestStreak == bestStreak;

  @override
  int get hashCode => Object.hash(workDays, goalDays, completionRate, focusMinutes, averageWaterMl, bestStreak);

  @override
  String toString() =>
      'HistoryStats(work: $workDays, met: $goalDays, rate: $completionRate, focus: $focusMinutes, '
      'water: $averageWaterMl, best: $bestStreak)';
}

@immutable
class HistorySeries {
  const HistorySeries({required this.range, required this.days, required this.stats, this.routine});

  final HistoryRange range;

  /// The filtered routine, or null for every routine together.
  final RoutineType? routine;

  /// One entry per date, oldest first, ending yesterday.
  final List<HistoryDay> days;
  final HistoryStats stats;

  bool get isEmpty => days.every((d) => d.kind == HistoryDayKind.noData);
}

/// Pure: finalized summaries → the chart series and stats for [range] days
/// ending the day before [today], for one [routine] or all of them.
///
/// "All" uses the day's overall progress (mean over enabled routines) and
/// its qualified flag; a routine uses its own measure (ml for hydration)
/// against the threshold stored with the day.
HistorySeries buildHistorySeries(
  List<DailySummary> summaries, {
  required DateTime today,
  required HistoryRange range,
  RoutineType? routine,
}) {
  final day0 = dateOnly(today);
  final first = addDays(day0, -range.days);
  final byDate = {
    for (final s in summaries)
      if (!s.date.isBefore(first) && s.date.isBefore(day0)) dateKey(s.date): s,
  };

  HistoryDay dayOf(DateTime date) {
    final s = byDate[dateKey(date)];
    if (s == null) return HistoryDay(date: date, kind: HistoryDayKind.noData);
    if (routine == null) {
      final anyEnabled = s.routines.any((r) => r.enabled);
      if (!anyEnabled) return HistoryDay(date: date, kind: s.isWorkDay ? HistoryDayKind.off : HistoryDayKind.rest);
      final percent = s.overallProgress * 100;
      return s.isWorkDay
          ? HistoryDay(date: date, kind: HistoryDayKind.work, percent: percent, goalMet: s.qualified)
          : HistoryDay(date: date, kind: HistoryDayKind.rest, percent: percent);
    }
    final r = s.routines.where((r) => r.type == routine).firstOrNull;
    if (r == null || !r.enabled) {
      return HistoryDay(date: date, kind: s.isWorkDay ? HistoryDayKind.off : HistoryDayKind.rest);
    }
    final measure = s.measureOf(r);
    final percent = measure.fraction * 100;
    return s.isWorkDay
        ? HistoryDay(
            date: date,
            kind: HistoryDayKind.work,
            percent: percent,
            goalMet: measure.reaches(s.thresholdPercent),
          )
        : HistoryDay(date: date, kind: HistoryDayKind.rest, percent: percent);
  }

  final days = [for (var i = 0; i < range.days; i++) dayOf(addDays(first, i))];
  final work = days.where((d) => d.kind == HistoryDayKind.work).toList();
  final windowSummaries = byDate.values.toList();
  final workSummaries = windowSummaries.where((s) => s.isWorkDay).toList();

  return HistorySeries(
    range: range,
    routine: routine,
    days: days,
    stats: HistoryStats(
      workDays: work.length,
      goalDays: work.where((d) => d.goalMet).length,
      completionRate: work.isEmpty ? null : work.fold<double>(0, (sum, d) => sum + d.percent!) / work.length,
      focusMinutes: windowSummaries.fold<int>(0, (sum, s) => sum + s.focusMinutes),
      averageWaterMl: workSummaries.isEmpty
          ? null
          : (workSummaries.fold<int>(0, (sum, s) => sum + s.waterMl) / workSummaries.length).round(),
      bestStreak: const StreakCalculator()(windowSummaries, today: day0).best,
    ),
  );
}
