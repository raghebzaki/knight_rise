import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/features/cycle/presentation/bloc/cycle_bloc.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';

import '../../helpers/fakes.dart';
import '../../helpers/tz.dart';

void main() {
  late FakeRoutineRepository routines;
  late FakeWorkScheduleRepository schedule;
  late FakeReminderEventRepository events;
  late FakeSettingsRepository settings;
  late FixedClock clock;

  setUp(() {
    routines = FakeRoutineRepository();
    schedule = FakeWorkScheduleRepository();
    events = FakeReminderEventRepository();
    settings = FakeSettingsRepository();
    clock = FixedClock(at(cairo, 2026, 10, 5, 9, 50)); // Monday
  });

  CycleBloc build() => CycleBloc(
    WatchCycleInputs(routines, schedule, events, settings),
    const BuildCycleSnapshot(ReminderPlanner()),
    CompleteRoutine(events, settings, clock),
    SnoozeRoutine(events, clock, cairo),
    clock,
    cairo,
  );

  RoutineStatus statusOf(CycleState s, RoutineType t) => s.snapshot!.viewOf(t)!.status;

  blocTest<CycleBloc, CycleState>(
    'emits a ready snapshot once inputs arrive',
    build: build,
    act: (b) => b.add(const CycleStarted()),
    wait: const Duration(milliseconds: 50),
    expect: () => [
      isA<CycleState>()
          .having((s) => s.status, 'status', CycleStatus.ready)
          .having((s) => statusOf(s, RoutineType.hydration), 'hydration', StatusDue(at(cairo, 2026, 10, 5, 9, 45))),
    ],
  );

  blocTest<CycleBloc, CycleState>(
    'completing a due routine records it and moves it to upcoming',
    build: build,
    act: (b) async {
      b.add(const CycleStarted());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.add(const RoutineCompleted(RoutineType.hydration));
    },
    wait: const Duration(milliseconds: 80),
    skip: 1,
    expect: () => [
      isA<CycleState>()
          .having(
            (s) => statusOf(s, RoutineType.hydration),
            'hydration',
            StatusUpcoming(at(cairo, 2026, 10, 5, 10, 35)),
          )
          .having((s) => s.snapshot!.waterMlToday, 'water', 250)
          .having((s) => s.snapshot!.viewOf(RoutineType.hydration)!.doneToday, 'done', 1),
    ],
    verify: (_) => expect(events.all.single.outcome, ReminderOutcome.done),
  );

  blocTest<CycleBloc, CycleState>(
    'snoozing marks the routine snoozed for 10 minutes',
    build: build,
    act: (b) async {
      b.add(const CycleStarted());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.add(const RoutineSnoozed(RoutineType.eyeRest));
    },
    wait: const Duration(milliseconds: 80),
    skip: 1,
    expect: () => [
      isA<CycleState>().having(
        (s) => statusOf(s, RoutineType.eyeRest),
        'eyeRest',
        StatusSnoozed(at(cairo, 2026, 10, 5, 10)),
      ),
    ],
  );

  blocTest<CycleBloc, CycleState>(
    'refresh after the clock moves re-derives status without new data',
    build: build,
    act: (b) async {
      clock.current = at(cairo, 2026, 10, 5, 8, 30); // before work
      b.add(const CycleStarted());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      clock.current = at(cairo, 2026, 10, 5, 9, 10);
      b.add(const CycleRefreshRequested());
    },
    wait: const Duration(milliseconds: 50),
    expect: () => [
      isA<CycleState>().having((s) => s.snapshot!.onDuty, 'onDuty', false),
      isA<CycleState>().having((s) => s.snapshot!.onDuty, 'onDuty', true),
    ],
  );
}
