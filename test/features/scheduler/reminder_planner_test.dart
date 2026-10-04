import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_window.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/tz.dart';

// 2026-10-05 is a Monday; 2026-10-08 a Thursday; 2026-10-09 a Friday; 2026-10-11 a Sunday.
const hydration = Routine(type: RoutineType.hydration, intervalMinutes: 45, dailyTarget: 8);
const stretch = Routine(type: RoutineType.stretch, intervalMinutes: 60, dailyTarget: 6);
const eyeRest = Routine(type: RoutineType.eyeRest, intervalMinutes: 20, dailyTarget: 12);

const planner = ReminderPlanner();

PlannerInput input({
  required DateTime now,
  List<Routine> routines = const [hydration],
  WorkSchedule? schedule,
  tz.Location? location,
  Map<RoutineType, RoutineHistory> history = const {},
  List<ShieldWindow> shields = const [],
}) => PlannerInput(
  routines: routines,
  schedule: schedule ?? WorkSchedule.standard(),
  location: location ?? cairo,
  now: now,
  history: history,
  shields: shields,
);

List<String> hm(List<PlannedReminder> plan, tz.Location l) => [
  for (final p in plan)
    () {
      final t = tz.TZDateTime.from(p.fireAt, l);
      return '${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }(),
];

void main() {
  group('plan()', () {
    test('rolling interval anchors to the start of the work window', () {
      final plan = planner.plan(input(now: at(cairo, 2026, 10, 5, 9)));
      expect(hm(plan, cairo).take(3), ['5 09:45', '5 10:30', '5 11:15']);
      // Last slot must stay inside the 17:00 window end.
      expect(hm(plan, cairo).where((s) => s.startsWith('5 ')).last, '5 16:30');
    });

    test('skips nights and weekends: Thursday evening → Sunday morning', () {
      const longPlanner = ReminderPlanner(horizon: Duration(hours: 72));
      final plan = longPlanner.plan(input(now: at(cairo, 2026, 10, 8, 16, 50)));
      expect(hm(plan, cairo).first, '11 09:45'); // Sunday 11 Oct
    });

    test('rolling: completion restarts the interval', () {
      final plan = planner.plan(
        input(
          now: at(cairo, 2026, 10, 5, 10, 10),
          history: {RoutineType.hydration: RoutineHistory(lastDoneAt: at(cairo, 2026, 10, 5, 10, 10))},
        ),
      );
      expect(hm(plan, cairo).first, '5 10:55');
    });

    test('fixed grid: completion keeps the grid', () {
      final plan = planner.plan(
        input(
          now: at(cairo, 2026, 10, 5, 10, 10),
          routines: [hydration.copyWith(mode: ScheduleMode.fixedGrid)],
          history: {RoutineType.hydration: RoutineHistory(lastDoneAt: at(cairo, 2026, 10, 5, 10, 10))},
        ),
      );
      expect(hm(plan, cairo).first, '5 10:30');
    });

    test('rolling: snooze fires at snoozedUntil, then continues from there', () {
      final plan = planner.plan(
        input(
          now: at(cairo, 2026, 10, 5, 9, 46),
          history: {RoutineType.hydration: RoutineHistory(snoozedUntil: at(cairo, 2026, 10, 5, 9, 56))},
        ),
      );
      expect(hm(plan, cairo).take(2), ['5 09:56', '5 10:41']);
    });

    test('fixed grid: snooze replaces the skipped slot only', () {
      final plan = planner.plan(
        input(
          now: at(cairo, 2026, 10, 5, 9, 46),
          routines: [hydration.copyWith(mode: ScheduleMode.fixedGrid)],
          history: {RoutineType.hydration: RoutineHistory(snoozedUntil: at(cairo, 2026, 10, 5, 9, 56))},
        ),
      );
      expect(hm(plan, cairo).take(2), ['5 09:56', '5 10:30']);
    });

    test('a snooze older than the last completion is ignored', () {
      final plan = planner.plan(
        input(
          now: at(cairo, 2026, 10, 5, 10),
          history: {
            RoutineType.hydration: RoutineHistory(
              snoozedUntil: at(cairo, 2026, 10, 5, 9, 56),
              lastDoneAt: at(cairo, 2026, 10, 5, 10),
            ),
          },
        ),
      );
      expect(hm(plan, cairo).first, '5 10:45');
    });

    test('reminders within 5 minutes merge into one notification', () {
      final plan = planner.plan(input(now: at(cairo, 2026, 10, 5, 9), routines: [hydration, stretch, eyeRest]));
      // eyeRest 09:20, 09:40 + hydration 09:45 → merged at 09:40.
      expect(plan[0].types, {RoutineType.eyeRest});
      expect(hm(plan, cairo)[1], '5 09:40');
      expect(plan[1].types, {RoutineType.eyeRest, RoutineType.hydration});
      // stretch 10:00 + eyeRest 10:00 share a slot.
      expect(hm(plan, cairo)[2], '5 10:00');
      expect(plan[2].types, {RoutineType.eyeRest, RoutineType.stretch});
    });

    test('respects maxCount and the horizon', () {
      final every = WorkSchedule(
        days: {
          for (var d = 1; d <= 7; d++) d: [TimeWindow.hm(0, 0, 24, 0)],
        },
      );
      final plan = planner.plan(
        input(now: at(cairo, 2026, 10, 5, 12), routines: [eyeRest.copyWith(intervalMinutes: 5)], schedule: every),
      );
      expect(plan, hasLength(50));

      const shortHorizon = ReminderPlanner(horizon: Duration(hours: 2));
      final short = shortHorizon.plan(input(now: at(cairo, 2026, 10, 5, 9), routines: [hydration]));
      expect(hm(short, cairo), ['5 09:45', '5 10:30']);
    });

    test('Shield windows suppress reminders inside them', () {
      final plan = planner.plan(
        input(
          now: at(cairo, 2026, 10, 5, 9),
          shields: [ShieldWindow(start: at(cairo, 2026, 10, 5, 9, 30), end: at(cairo, 2026, 10, 5, 11))],
        ),
      );
      expect(hm(plan, cairo).first, '5 11:15');
    });

    test('disabled routines are not planned', () {
      final plan = planner.plan(input(now: at(cairo, 2026, 10, 5, 9), routines: [hydration.copyWith(enabled: false)]));
      expect(plan, isEmpty);
    });

    test('split shifts restart the interval in each window', () {
      final split = WorkSchedule(
        days: {
          1: [TimeWindow.hm(9, 0, 12, 0), TimeWindow.hm(13, 0, 17, 0)],
        },
      );
      final plan = planner.plan(input(now: at(cairo, 2026, 10, 5, 11), schedule: split));
      expect(hm(plan, cairo).take(3), ['5 11:15', '5 13:45', '5 14:30']);
    });

    test('DST spring-forward: intervals are real elapsed time', () {
      // New York, Sunday 2026-03-08: 02:00 EST jumps to 03:00 EDT.
      final night = WorkSchedule(
        days: {
          7: [TimeWindow.hm(1, 0, 5, 0)],
        },
      );
      final plan = planner.plan(
        input(
          now: at(newYork, 2026, 3, 8, 0, 30),
          location: newYork,
          routines: [stretch.copyWith(mode: ScheduleMode.fixedGrid)],
          schedule: night,
        ),
      );
      expect(hm(plan, newYork), ['8 03:00', '8 04:00']);
      expect(plan[1].fireAt.difference(plan[0].fireAt), const Duration(hours: 1));
    });

    test('DST fall-back: the work window keeps its wall-clock hours', () {
      // New York, Sunday 2026-11-01: 02:00 EDT falls back to 01:00 EST.
      final day = WorkSchedule(
        days: {
          7: [TimeWindow.hm(9, 0, 17, 0)],
        },
      );
      final plan = planner.plan(input(now: at(newYork, 2026, 11, 1, 8), location: newYork, schedule: day));
      expect(hm(plan, newYork).first, '1 09:45');
      expect(hm(plan, newYork).last, '1 16:30');
    });
  });

  group('statusOf()', () {
    test('due when a slot passed without completion', () {
      final s = planner.statusOf(RoutineType.hydration, input(now: at(cairo, 2026, 10, 5, 9, 50)));
      expect(s, StatusDue(at(cairo, 2026, 10, 5, 9, 45)));
    });

    test('upcoming after completing a due routine', () {
      final s = planner.statusOf(
        RoutineType.hydration,
        input(
          now: at(cairo, 2026, 10, 5, 9, 50),
          history: {RoutineType.hydration: RoutineHistory(lastDoneAt: at(cairo, 2026, 10, 5, 9, 50))},
        ),
      );
      expect(s, StatusUpcoming(at(cairo, 2026, 10, 5, 10, 35)));
    });

    test('snoozed while the snooze is running', () {
      final until = at(cairo, 2026, 10, 5, 10);
      final s = planner.statusOf(
        RoutineType.hydration,
        input(
          now: at(cairo, 2026, 10, 5, 9, 55),
          history: {RoutineType.hydration: RoutineHistory(snoozedUntil: until, snoozesSinceDone: 1)},
        ),
      );
      expect(s, StatusSnoozed(until));
    });

    test('off duty at night, with the next work start across midnight', () {
      final s = planner.statusOf(RoutineType.hydration, input(now: at(cairo, 2026, 10, 5, 23, 30)));
      expect(s, StatusOffDuty(at(cairo, 2026, 10, 6, 9)));
    });

    test('disabled', () {
      final s = planner.statusOf(
        RoutineType.hydration,
        input(now: at(cairo, 2026, 10, 5, 10), routines: [hydration.copyWith(enabled: false)]),
      );
      expect(s, const StatusDisabled());
    });
  });

  group('nextChangeAt()', () {
    test('is the next slot during work hours', () {
      final t = planner.nextChangeAt(input(now: at(cairo, 2026, 10, 5, 9), routines: [eyeRest]));
      expect(t, at(cairo, 2026, 10, 5, 9, 20));
    });

    test('is local midnight in the evening', () {
      final t = planner.nextChangeAt(input(now: at(cairo, 2026, 10, 5, 18)));
      expect(t, at(cairo, 2026, 10, 6));
    });

    test('is the window end when no slot fits before it', () {
      final t = planner.nextChangeAt(input(now: at(cairo, 2026, 10, 5, 16, 40)));
      expect(t, at(cairo, 2026, 10, 5, 17));
    });
  });

  group('PlannedReminder.notificationId', () {
    test('is deterministic and distinguishes routines and slots', () {
      final t = at(cairo, 2026, 10, 5, 9, 45);
      final a = PlannedReminder(fireAt: t, types: const {RoutineType.hydration});
      final b = PlannedReminder(fireAt: t, types: const {RoutineType.hydration});
      final c = PlannedReminder(fireAt: t, types: const {RoutineType.stretch});
      final d = PlannedReminder(fireAt: t.add(const Duration(minutes: 1)), types: const {RoutineType.hydration});
      expect(a.notificationId, b.notificationId);
      expect({a.notificationId, c.notificationId, d.notificationId}, hasLength(3));
      expect(a.notificationId, isNonNegative);
    });
  });
}
