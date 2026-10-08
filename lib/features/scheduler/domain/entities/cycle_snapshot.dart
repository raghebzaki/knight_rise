import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';

part 'cycle_snapshot.freezed.dart';

/// One routine as the dashboard sees it.
@freezed
abstract class RoutineView with _$RoutineView {
  const factory RoutineView({
    required Routine routine,
    required RoutineStatus status,
    required int doneToday,
    required bool canSnooze,

    /// Share of today's goal reached, 0..1 (`QuestMeasure`: ml for hydration).
    required double progress,
  }) = _RoutineView;

  const RoutineView._();

  RoutineType get type => routine.type;
}

/// Everything the home screen renders, computed at [computedAt].
@freezed
abstract class CycleSnapshot with _$CycleSnapshot {
  const factory CycleSnapshot({
    required DateTime computedAt,
    required List<RoutineView> routines,
    required bool onDuty,
    required int waterMlToday,
    required int waterTargetMl,
    required DateTime nextChangeAt,
    PlannedReminder? nextUp,
    DateTime? nextWorkStart,

    /// The Shield covering [computedAt], if any (latest started).
    ShieldSession? activeShield,

    /// Today's day-off / working-late override, if any.
    DayOverride? todayOverride,

    /// The first planned recovery ("Shield down") reminder, if the plan has one.
    PlannedReminder? nextRecovery,
  }) = _CycleSnapshot;

  const CycleSnapshot._();

  RoutineView? viewOf(RoutineType type) => routines.where((r) => r.type == type).firstOrNull;

  /// Mean completion over enabled routines, 0..1.
  double get overallProgress {
    final active = routines.where((r) => r.routine.enabled).toList();
    if (active.isEmpty) return 0;
    return active.fold<double>(0, (s, r) => s + r.progress) / active.length;
  }
}
