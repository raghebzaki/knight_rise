import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/handle_reminder_action.dart';

import '../../helpers/fakes.dart';
import '../../helpers/tz.dart';

void main() {
  late FakeReminderEventRepository events;
  late FakeScheduleReconciler reconciler;
  late FixedClock clock;
  late HandleReminderAction handle;
  final slot = at(cairo, 2026, 10, 5, 9, 45);

  ReminderAction action(ReminderActionKind kind, Set<RoutineType> types) =>
      ReminderAction(kind: kind, types: types, scheduledAt: slot, notificationId: 7);

  setUp(() {
    events = FakeReminderEventRepository();
    reconciler = FakeScheduleReconciler();
    clock = FixedClock(at(cairo, 2026, 10, 5, 9, 50));
    handle = HandleReminderAction(
      CompleteRoutine(events, FakeSettingsRepository(), clock),
      SnoozeRoutine(events, clock, cairo),
      reconciler,
    );
  });

  test('done with {hydration, eyeRest} completes both, logs water, reconciles once', () async {
    await handle(action(ReminderActionKind.done, {RoutineType.hydration, RoutineType.eyeRest}));

    expect(events.all.length, 2);
    expect(events.all.every((e) => e.outcome == ReminderOutcome.done), isTrue);
    expect(events.all.map((e) => e.type).toSet(), {RoutineType.hydration, RoutineType.eyeRest});
    expect(events.all.every((e) => e.scheduledAt == slot), isTrue);
    expect(events.all.firstWhere((e) => e.type == RoutineType.hydration).waterMl, 250);
    expect(events.all.firstWhere((e) => e.type == RoutineType.eyeRest).waterMl, isNull);
    expect(reconciler.calls, [ReconcileTrigger.action]);
  });

  test('snooze writes snoozed events and respects the max of 3', () async {
    for (var i = 0; i < 4; i++) {
      await handle(action(ReminderActionKind.snooze, {RoutineType.stretch}));
    }
    final snoozes = events.all.where((e) => e.outcome == ReminderOutcome.snoozed).toList();
    expect(snoozes.length, kMaxSnoozes);
    expect(snoozes.first.snoozedUntil, clock.now().add(kSnoozeDuration));
    expect(snoozes.first.scheduledAt, slot);
    expect(reconciler.calls.length, 4);
  });

  test('open does nothing', () async {
    await handle(action(ReminderActionKind.open, {RoutineType.hydration}));
    expect(events.all, isEmpty);
    expect(reconciler.calls, isEmpty);
  });
}
