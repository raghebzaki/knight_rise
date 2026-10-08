import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_window.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/tz.dart';

// 2026-10-05 is a Monday (work day), 2026-10-09 a Friday (off).
const hydration = Routine(type: RoutineType.hydration, intervalMinutes: 45, dailyTarget: 8);
const stretch = Routine(type: RoutineType.stretch, intervalMinutes: 60, dailyTarget: 6);
const eyeRest = Routine(type: RoutineType.eyeRest, intervalMinutes: 20, dailyTarget: 12);

const planner = ReminderPlanner();

tz.TZDateTime mon(int h, [int m = 0, int s = 0]) => tz.TZDateTime(cairo, 2026, 10, 5, h, m, s);

ShieldWindow shield(DateTime start, DateTime end, {DateTime? endedAt}) =>
    ShieldWindow(start: start, end: end, endedAt: endedAt);

PlannerInput input({
  required DateTime now,
  List<Routine> routines = const [hydration],
  List<ShieldWindow> shields = const [],
  bool recoverOnExit = true,
  Map<RoutineType, RoutineHistory> history = const {},
  List<DayOverride> overrides = const [],
  WorkSchedule? schedule,
}) => PlannerInput(
  routines: routines,
  schedule: schedule ?? WorkSchedule.standard(),
  location: cairo,
  now: now,
  history: history,
  shields: shields,
  recoverOnExit: recoverOnExit,
  overrides: overrides,
);

String hm(PlannedReminder p) {
  final t = tz.TZDateTime.from(p.fireAt, cairo);
  return '${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

List<String> times(List<PlannedReminder> plan) => plan.map(hm).toList();

DayOverride off(int day) => DayOverride(date: DateTime.utc(2026, 10, day), kind: DayOverrideKind.off);
DayOverride extend(int day, int minutes) =>
    DayOverride(date: DateTime.utc(2026, 10, day), kind: DayOverrideKind.extend, extendMinutes: minutes);

void main() {
  group('Shield suppression and recovery', () {
    test('slots inside a Shield are suppressed; recovery ping fires at the end', () {
      final plan = planner.plan(input(now: mon(9), shields: [shield(mon(9, 30), mon(11))]));
      // Hydration 09:45 and 10:30 are held back; 11:00 recovery, then 11:15.
      expect(times(plan).take(3), ['5 11:00', '5 11:15', '5 12:00']);
      expect(plan.first.recovery, isTrue);
      expect(plan[1].recovery, isFalse);
    });

    test('recovery lists exactly the routines that had a slot inside the Shield', () {
      final plan = planner.plan(
        input(now: mon(9, 50), routines: const [hydration, stretch], shields: [shield(mon(10), mon(10, 20))]),
      );
      // Stretch 10:00 is inside; hydration (09:45, 10:30) is not.
      expect(plan.first, PlannedReminder(fireAt: mon(10, 20), types: const {RoutineType.stretch}, recovery: true));
      expect(hm(plan[1]), '5 10:30');
      expect(plan[1].types, {RoutineType.hydration});
    });

    test('no recovery when recoverOnExit is false', () {
      final plan = planner.plan(input(now: mon(9), shields: [shield(mon(9, 30), mon(11))], recoverOnExit: false));
      expect(plan.any((p) => p.recovery), isFalse);
      expect(hm(plan.first), '5 11:15');
    });

    test('no recovery when nothing was suppressed', () {
      // Hydration slots are 09:45 and 10:30: neither is inside 10:05-10:20.
      final plan = planner.plan(input(now: mon(9, 50), shields: [shield(mon(10, 5), mon(10, 20))]));
      expect(plan.any((p) => p.recovery), isFalse);
      expect(times(plan).first, '5 10:30');
    });

    test('no recovery when the Shield ends outside work hours', () {
      final plan = planner.plan(input(now: mon(16), shields: [shield(mon(16, 20), mon(17, 30))]));
      expect(plan.any((p) => p.recovery), isFalse);
    });

    test('no recovery at exactly the window end (end is exclusive)', () {
      final plan = planner.plan(input(now: mon(16), shields: [shield(mon(16, 20), mon(17))]));
      expect(plan.any((p) => p.recovery), isFalse);
    });

    test('disabled routines are never part of a recovery', () {
      final plan = planner.plan(
        input(
          now: mon(9, 50),
          routines: [hydration.copyWith(enabled: false), stretch],
          shields: [shield(mon(9, 30), mon(10, 20))],
        ),
      );
      expect(plan.first.types, {RoutineType.stretch});
      expect(plan.first.recovery, isTrue);
    });

    test('Shield started while a routine is due: hydration is in the recovery', () {
      // Hydration due since 09:45; Shield 09:50-10:40 also holds back 10:30.
      final i = input(now: mon(9, 50), shields: [shield(mon(9, 50), mon(10, 40))]);
      expect(planner.statusOf(RoutineType.hydration, i), StatusShielded(mon(10, 40)));
      final plan = planner.plan(i);
      expect(plan.first, PlannedReminder(fireAt: mon(10, 40), types: const {RoutineType.hydration}, recovery: true));
    });

    test('slots superseded by a later completion do not count', () {
      // Done at 10:00 (inside the Shield) moves hydration to 10:45, outside 09:30-10:40.
      final plan = planner.plan(
        input(
          now: mon(10, 10),
          shields: [shield(mon(9, 30), mon(10, 40))],
          history: {RoutineType.hydration: RoutineHistory(lastDoneAt: mon(10))},
        ),
      );
      expect(plan.any((p) => p.recovery), isFalse);
      expect(times(plan).first, '5 10:45');
    });

    test('candidate slots count even when they are already in the past', () {
      // 09:45 was suppressed by the 09:30-10:30 Shield, now is 10:00.
      final plan = planner.plan(input(now: mon(10), shields: [shield(mon(9, 30), mon(10, 30))]));
      expect(plan.first.recovery, isTrue);
      expect(hm(plan.first), '5 10:30');
    });

    test('early manual end: recovery fires one minute after the end', () {
      final w = shield(mon(9, 30), mon(10), endedAt: mon(10));
      final plan = planner.plan(input(now: mon(10, 0, 30), shields: [w]));
      expect(plan.first, PlannedReminder(fireAt: mon(10, 1), types: const {RoutineType.hydration}, recovery: true));
    });

    test('early manual end: no recovery once the +1 min moment has passed', () {
      final w = shield(mon(9, 30), mon(10), endedAt: mon(10));
      for (final now in [mon(10, 1), mon(10, 1, 30), mon(10, 2), mon(10, 5)]) {
        final plan = planner.plan(input(now: now, shields: [w]));
        expect(plan.any((p) => p.recovery), isFalse, reason: '$now');
      }
    });

    test('overlapping Shields merge into one recovery at the final end', () {
      final plan = planner.plan(
        input(now: mon(9), shields: [shield(mon(9, 30), mon(10)), shield(mon(9, 50), mon(10, 40))]),
      );
      final recoveries = plan.where((p) => p.recovery).toList();
      expect(recoveries.map(hm), ['5 10:40']);
    });

    test('touching Shields (replace-in-place) merge as well', () {
      final plan = planner.plan(
        input(now: mon(9), shields: [shield(mon(9, 30), mon(10)), shield(mon(10), mon(10, 40))]),
      );
      expect(plan.where((p) => p.recovery).map(hm), ['5 10:40']);
    });

    test('separate Shields each get their own recovery', () {
      final plan = planner.plan(
        input(now: mon(9), shields: [shield(mon(9, 30), mon(10)), shield(mon(10, 25), mon(10, 35))]),
      );
      expect(plan.where((p) => p.recovery).map(hm), ['5 10:00', '5 10:35']);
    });

    test('a snooze that lands inside a Shield ends up in the recovery', () {
      // Hydration snoozed until 10:00; Shield 09:55-10:10 holds back that slot.
      final plan = planner.plan(
        input(
          now: mon(9, 56),
          shields: [shield(mon(9, 55), mon(10, 10))],
          history: {RoutineType.hydration: RoutineHistory(snoozedUntil: mon(10), snoozesSinceDone: 1)},
        ),
      );
      expect(plan.first, PlannedReminder(fireAt: mon(10, 10), types: const {RoutineType.hydration}, recovery: true));
    });

    test('recovery merges with a regular slot within 5 minutes and keeps recovery = true', () {
      final plan = planner.plan(
        input(now: mon(9), routines: const [hydration, stretch], shields: [shield(mon(9, 40), mon(10, 27))]),
      );
      // Recovery 10:27 absorbs hydration's regular 10:30 slot.
      expect(plan.first.recovery, isTrue);
      expect(hm(plan.first), '5 10:27');
      expect(plan.first.types, {RoutineType.hydration, RoutineType.stretch});
      expect(times(plan).contains('5 10:30'), isFalse);
    });

    test('recovery earlier than a merged regular slot keeps its own time', () {
      // Regular 09:45 hydration merges with a recovery 10:27? no: a recovery at
      // 09:44 (Shield 09:00-09:44, eyeRest slot 09:20 inside) and hydration 09:45.
      final plan = planner.plan(
        input(now: mon(9), routines: const [hydration, eyeRest], shields: [shield(mon(9), mon(9, 44))]),
      );
      expect(hm(plan.first), '5 09:44');
      expect(plan.first.recovery, isTrue);
      expect(plan.first.types, {RoutineType.hydration, RoutineType.eyeRest});
    });

    test('recoveries outside the planning horizon are not planned', () {
      final plan = planner.plan(
        input(
          now: mon(9),
          shields: [shield(tz.TZDateTime(cairo, 2026, 10, 7, 10), tz.TZDateTime(cairo, 2026, 10, 7, 11))],
        ),
      );
      expect(plan.any((p) => p.recovery), isFalse);
    });
  });

  group('statusOf with Shield', () {
    test('Shielded beats Due, Upcoming and Snoozed', () {
      final w = shield(mon(9, 30), mon(10, 30));
      expect(planner.statusOf(RoutineType.hydration, input(now: mon(10), shields: [w])), StatusShielded(mon(10, 30)));
      // Snoozed too.
      final snoozed = input(
        now: mon(10),
        shields: [w],
        history: {RoutineType.hydration: RoutineHistory(snoozedUntil: mon(10, 5), snoozesSinceDone: 1)},
      );
      expect(planner.statusOf(RoutineType.hydration, snoozed), StatusShielded(mon(10, 30)));
    });

    test('Shielded reports the merged end', () {
      final i = input(now: mon(10), shields: [shield(mon(9, 30), mon(10, 30)), shield(mon(10, 30), mon(11))]);
      expect(planner.statusOf(RoutineType.hydration, i), StatusShielded(mon(11)));
    });

    test('Disabled and OffDuty still win', () {
      final w = shield(mon(9, 30), mon(10, 30));
      expect(
        planner.statusOf(
          RoutineType.hydration,
          input(now: mon(10), routines: [hydration.copyWith(enabled: false)], shields: [w]),
        ),
        const StatusDisabled(),
      );
      final late = input(now: mon(17, 10), shields: [shield(mon(16, 30), mon(18))]);
      expect(planner.statusOf(RoutineType.hydration, late), isA<StatusOffDuty>());
    });

    test('a Shield that already ended no longer shields', () {
      final i = input(now: mon(10, 31), shields: [shield(mon(9, 30), mon(10, 30))]);
      expect(planner.statusOf(RoutineType.hydration, i), isNot(isA<StatusShielded>()));
    });

    test('a manually ended Shield no longer shields after its early end', () {
      final i = input(
        now: mon(10, 5),
        shields: [shield(mon(9, 30), mon(10), endedAt: mon(10))],
      );
      expect(planner.statusOf(RoutineType.hydration, i), isNot(isA<StatusShielded>()));
    });
  });

  group('nextChangeAt with Shield', () {
    test('includes Shield start', () {
      final i = input(now: mon(9, 10), shields: [shield(mon(9, 20), mon(9, 40))]);
      expect(planner.nextChangeAt(i), mon(9, 20));
    });

    test('includes Shield end', () {
      final i = input(now: mon(9, 25), shields: [shield(mon(9, 20), mon(9, 40))]);
      expect(planner.nextChangeAt(i), mon(9, 40));
    });

    test('includes endedAt + 1 min', () {
      final i = input(
        now: mon(9, 20, 30),
        shields: [shield(mon(9), mon(9, 20), endedAt: mon(9, 20))],
      );
      expect(planner.nextChangeAt(i), mon(9, 21));
    });
  });

  group('PlannedReminder.recovery', () {
    test('participates in equality, hashCode and toString; not in the notification id', () {
      final a = PlannedReminder(fireAt: mon(10), types: const {RoutineType.hydration});
      final b = PlannedReminder(fireAt: mon(10), types: const {RoutineType.hydration}, recovery: true);
      expect(a, isNot(b));
      expect(a.hashCode, isNot(b.hashCode));
      expect(b.toString(), contains('recovery'));
      expect(a.notificationId, b.notificationId);
    });
  });

  group('day overrides', () {
    test('day off: no plan that day, OffDuty pointing at the next work day', () {
      const long = ReminderPlanner(horizon: Duration(hours: 48));
      final i = input(now: mon(9, 10), overrides: [off(5)]);
      expect(long.plan(i).map(hm).first, '6 09:45');
      expect(planner.plan(i), isEmpty);
      expect(planner.statusOf(RoutineType.hydration, i), StatusOffDuty(tz.TZDateTime(cairo, 2026, 10, 6, 9)));
      expect(planner.currentWindow(i), isNull);
      expect(planner.nextWorkStart(i), tz.TZDateTime(cairo, 2026, 10, 6, 9));
    });

    test('day off on Thursday jumps over the weekend', () {
      final thu = tz.TZDateTime(cairo, 2026, 10, 8, 10);
      final i = input(now: thu, overrides: [off(8)]);
      expect(planner.statusOf(RoutineType.hydration, i), StatusOffDuty(tz.TZDateTime(cairo, 2026, 10, 11, 9)));
    });

    test('overrides for other dates do not affect today', () {
      final i = input(now: mon(9, 10), overrides: [off(6), extend(6, 120), off(4)]);
      expect(planner.plan(i), isNotEmpty);
      expect(planner.currentWindow(i)!.end, mon(17));
    });

    test('extend +60: window ends at 18:00, last slots reach 17:40, nextChangeAt is 18:00', () {
      final i = input(now: mon(17, 50), routines: const [eyeRest], overrides: [extend(5, 60)]);
      expect(planner.currentWindow(i)!.end, mon(18));
      expect(planner.nextChangeAt(i), mon(18));

      final early = input(now: mon(16, 50), routines: const [eyeRest], overrides: [extend(5, 60)]);
      final today = planner.plan(early).where((p) => hm(p).startsWith('5 ')).toList();
      expect(hm(today.last), '5 17:40');
      // Without the override the last eye-rest slot is 16:40.
      final plain = planner.plan(input(now: mon(16, 50), routines: const [eyeRest]));
      expect(hm(plain.first), '6 09:20'); // tomorrow
    });

    test('extend only stretches the LAST window of a split shift', () {
      final split = WorkSchedule(
        days: {
          1: [TimeWindow.hm(9, 0, 12, 0), TimeWindow.hm(13, 0, 17, 0)],
        },
      );
      final windowsEnds = [
        for (final t in [mon(10), mon(14)])
          planner.currentWindow(input(now: t, schedule: split, overrides: [extend(5, 30)]))!.end,
      ];
      expect(windowsEnds, [mon(12), mon(17, 30)]);
    });

    test('extend is capped at midnight', () {
      final night = WorkSchedule(
        days: {
          1: [TimeWindow.hm(20, 0, 23, 30)],
        },
      );
      final i = input(now: mon(23, 50), schedule: night, overrides: [extend(5, 240)]);
      final w = planner.currentWindow(i)!;
      expect(w.end, tz.TZDateTime(cairo, 2026, 10, 6));
      final plan = planner.plan(input(now: mon(20, 10), schedule: night, overrides: [extend(5, 240)]));
      expect(hm(plan.where((p) => hm(p).startsWith('5 ')).last), '5 23:45');
    });

    test('extending a day without windows does nothing', () {
      final fri = tz.TZDateTime(cairo, 2026, 10, 9, 10);
      final i = input(now: fri, overrides: [extend(9, 60)]);
      expect(planner.currentWindow(i), isNull);
    });

    test('Shield started late in an extended day still recovers inside the extension', () {
      final i = input(now: mon(17, 10), shields: [shield(mon(17, 10), mon(17, 50))], overrides: [extend(5, 60)]);
      expect(planner.statusOf(RoutineType.hydration, i), StatusShielded(mon(17, 50)));
      // hydration 17:15 (09:00 + 11 * 45min) is inside the Shield, so a recovery at 17:50 is planned.
      expect(
        planner.plan(i).first,
        PlannedReminder(fireAt: mon(17, 50), types: const {RoutineType.hydration}, recovery: true),
      );
    });

    test('date helpers', () {
      expect(dateKey(DateTime.utc(2026, 10, 5)), '2026-10-05');
      expect(parseDateKey('2026-10-05'), DateTime.utc(2026, 10, 5));
      expect(() => parseDateKey('2026-1-5'), throwsFormatException);
      expect(localDateOf(tz.TZDateTime(cairo, 2026, 10, 5, 23, 59), cairo), DateTime.utc(2026, 10, 5));
      // 22:30 UTC on the 5th is already the 6th in Cairo (UTC+3 until DST ends late October).
      expect(localDateOf(DateTime.utc(2026, 10, 5, 22, 30), cairo), DateTime.utc(2026, 10, 6));
      expect(dateOnly(DateTime(2026, 10, 5, 13, 30)), DateTime.utc(2026, 10, 5));
    });
  });
}
