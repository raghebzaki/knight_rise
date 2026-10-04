import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:knight_rise/features/settings/domain/entities/app_settings.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';

import '../../helpers/fakes.dart';
import '../../helpers/tz.dart';

void main() {
  group('historyFromEvents', () {
    test('a completion resets snoozes; later snoozes count up', () {
      final h = historyFromEvents([
        ReminderEvent(
          type: RoutineType.hydration,
          outcome: ReminderOutcome.snoozed,
          at: at(cairo, 2026, 10, 5, 9, 45),
          snoozedUntil: at(cairo, 2026, 10, 5, 9, 55),
        ),
        ReminderEvent(type: RoutineType.hydration, outcome: ReminderOutcome.done, at: at(cairo, 2026, 10, 5, 10)),
        ReminderEvent(
          type: RoutineType.hydration,
          outcome: ReminderOutcome.snoozed,
          at: at(cairo, 2026, 10, 5, 10, 45),
          snoozedUntil: at(cairo, 2026, 10, 5, 10, 55),
        ),
      ]);
      expect(
        h[RoutineType.hydration],
        RoutineHistory(
          lastDoneAt: at(cairo, 2026, 10, 5, 10),
          snoozedUntil: at(cairo, 2026, 10, 5, 10, 55),
          snoozesSinceDone: 1,
        ),
      );
    });
  });

  group('CompleteRoutine / SnoozeRoutine', () {
    late FakeReminderEventRepository events;
    late FakeSettingsRepository settings;
    late FixedClock clock;

    setUp(() {
      events = FakeReminderEventRepository();
      settings = FakeSettingsRepository();
      clock = FixedClock(at(cairo, 2026, 10, 5, 10));
    });

    test('hydration completion logs 250 ml; others log no water', () async {
      final complete = CompleteRoutine(events, settings, clock);
      await complete(RoutineType.hydration);
      await complete(RoutineType.stretch);
      expect(events.all.map((e) => e.waterMl), [250, null]);
      expect(events.all.every((e) => e.outcome == ReminderOutcome.done), isTrue);
    });

    test('waterMl overrides the per-tap default for hydration only', () async {
      final complete = CompleteRoutine(events, settings, clock);
      await complete(RoutineType.hydration, waterMl: 500);
      await complete(RoutineType.hydration);
      await complete(RoutineType.eyeRest, waterMl: 500);
      expect(events.all.map((e) => e.waterMl), [500, 250, null]);
    });

    test('snooze sets snoozedUntil = now + 10 min and stops after 3', () async {
      final snooze = SnoozeRoutine(events, clock, cairo);
      expect(await snooze(RoutineType.eyeRest), isTrue);
      expect(events.all.single.snoozedUntil, at(cairo, 2026, 10, 5, 10, 10));
      expect(await snooze(RoutineType.eyeRest), isTrue);
      expect(await snooze(RoutineType.eyeRest), isTrue);
      expect(await snooze(RoutineType.eyeRest), isFalse);
      expect(events.all, hasLength(3));

      await CompleteRoutine(events, settings, clock)(RoutineType.eyeRest);
      expect(await snooze(RoutineType.eyeRest), isTrue, reason: 'completion resets the snooze budget');
    });
  });

  group('BuildCycleSnapshot', () {
    const build = BuildCycleSnapshot(ReminderPlanner());

    CycleInputs inputs(List<ReminderEvent> today) => CycleInputs(
      routines: Routine.defaults,
      schedule: WorkSchedule.standard(),
      todayEvents: today,
      settings: const AppSettings(),
    );

    test('counts completions and water for today only', () {
      final yesterday = ReminderEvent(
        type: RoutineType.hydration,
        outcome: ReminderOutcome.done,
        at: at(cairo, 2026, 10, 4, 15),
        waterMl: 250,
      );
      final today = [
        for (final h in [9, 10])
          ReminderEvent(
            type: RoutineType.hydration,
            outcome: ReminderOutcome.done,
            at: at(cairo, 2026, 10, 5, h, 30),
            waterMl: 250,
          ),
      ];
      final s = build(inputs([yesterday, ...today]), now: at(cairo, 2026, 10, 5, 11), location: cairo);
      expect(s.viewOf(RoutineType.hydration)!.doneToday, 2);
      expect(s.waterMlToday, 500);
      expect(s.waterTargetMl, 2000);
      expect(s.onDuty, isTrue);
      // hydration 2/8, stretch 0/6, eye rest 0/12 → (0.25 + 0 + 0) / 3
      expect(s.overallProgress, closeTo(0.25 / 3, 1e-9));
    });

    test('off duty on Saturday with Sunday 09:00 as next work start', () {
      final s = build(inputs(const []), now: at(cairo, 2026, 10, 10, 12), location: cairo);
      expect(s.onDuty, isFalse);
      expect(s.nextWorkStart, at(cairo, 2026, 10, 11, 9));
      expect(s.routines.map((r) => r.status), everyElement(isA<StatusOffDuty>()));
    });

    test('canSnooze turns false after three snoozes', () {
      final snoozes = [
        for (var i = 0; i < 3; i++)
          ReminderEvent(
            type: RoutineType.stretch,
            outcome: ReminderOutcome.snoozed,
            at: at(cairo, 2026, 10, 5, 10, i * 10),
            snoozedUntil: at(cairo, 2026, 10, 5, 10, i * 10 + 10),
          ),
      ];
      final s = build(inputs(snoozes), now: at(cairo, 2026, 10, 5, 10, 45), location: cairo);
      expect(s.viewOf(RoutineType.stretch)!.canSnooze, isFalse);
      expect(s.viewOf(RoutineType.hydration)!.canSnooze, isTrue);
    });
  });
}
