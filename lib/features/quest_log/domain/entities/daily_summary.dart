import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:knight_rise/features/quest_log/domain/services/quest_measure.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';

part 'daily_summary.freezed.dart';

/// One routine's result on a finalized day, with the target and enabled flag
/// it had that day (later edits never rewrite history).
@freezed
abstract class RoutineDaySummary with _$RoutineDaySummary {
  const factory RoutineDaySummary({
    required RoutineType type,
    required int done,
    required int target,
    required bool enabled,
  }) = _RoutineDaySummary;
}

/// A finalized past day. Today is never summarized: it is computed live from
/// reminder events. Summaries are kept permanently and power streaks and the
/// history charts after raw events are pruned (90 days).
@freezed
abstract class DailySummary with _$DailySummary {
  const factory DailySummary({
    /// Local calendar date, date-only (`DateTime.utc(y, m, d)`).
    required DateTime date,

    /// False for rest days (no work window, or a "day off" override). Rest
    /// days neither extend nor break a streak.
    required bool isWorkDay,
    required int waterMl,
    required int waterTargetMl,
    required int focusMinutes,

    /// Streak threshold in force when the day was finalized.
    required int thresholdPercent,

    /// True when every enabled routine reached [thresholdPercent] of its target.
    required bool qualified,
    required DateTime finalizedAt,
    @Default(<RoutineDaySummary>[]) List<RoutineDaySummary> routines,
  }) = _DailySummary;

  const DailySummary._();

  /// Whether the day can extend or break a streak: a work day with at least
  /// one enabled routine. Every other day is neutral.
  bool get countsTowardStreak => isWorkDay && routines.any((r) => r.enabled);

  /// Mean progress over the enabled routines, 0..1 (0 when none is enabled).
  double get overallProgress {
    final enabled = routines.where((r) => r.enabled).toList();
    if (enabled.isEmpty) return 0;
    return enabled.fold<double>(0, (sum, r) => sum + measureOf(r).fraction) / enabled.length;
  }

  /// [routine]'s progress that day (hydration in ml).
  QuestMeasure measureOf(RoutineDaySummary routine) => QuestMeasure.of(
    routine.type,
    done: routine.done,
    target: routine.target,
    waterMl: waterMl,
    waterTargetMl: waterTargetMl,
  );
}
