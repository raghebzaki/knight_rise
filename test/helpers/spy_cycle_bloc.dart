import 'package:knight_rise/features/cycle/presentation/bloc/cycle_bloc.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';

import 'quest_log_harness.dart';
import 'tz.dart';

/// A real [CycleBloc] over the harness repositories that records every event it receives, so tests can assert
/// which completions and snoozes a UI gesture dispatched.
class SpyCycleBloc extends CycleBloc {
  SpyCycleBloc(QuestLogHarness h)
    : super(
        WatchCycleInputs(h.routines, h.schedule, h.events, h.settings, h.shields, h.overrides),
        const BuildCycleSnapshot(ReminderPlanner()),
        CompleteRoutine(h.events, h.settings, h.clock),
        SnoozeRoutine(h.events, h.clock, cairo),
        h.clock,
        cairo,
      );

  /// Every event, in order (including internal ones).
  final List<CycleEvent> seen = [];

  @override
  void onEvent(CycleEvent event) {
    seen.add(event);
    super.onEvent(event);
  }

  /// Routines completed through [RoutineCompleted], in order.
  List<RoutineType> get completed => [
    for (final e in seen)
      if (e is RoutineCompleted) e.type,
  ];

  /// Routines snoozed through [RoutineSnoozed], in order.
  List<RoutineType> get snoozed => [
    for (final e in seen)
      if (e is RoutineSnoozed) e.type,
  ];

  /// Clears the recorded events.
  void reset() => seen.clear();
}
