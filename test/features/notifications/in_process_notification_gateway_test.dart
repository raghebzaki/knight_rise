import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/features/notifications/data/in_process_notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/due_reminder.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/pending_reminder.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/notifications/domain/reminder_payload.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';

void main() {
  late FixedClock clock;
  late InProcessNotificationGateway gateway;
  final water = PlannedReminder(fireAt: DateTime.utc(2026, 10, 9, 9), types: const {RoutineType.hydration});
  final eyes = PlannedReminder(fireAt: DateTime.utc(2026, 10, 9, 10), types: const {RoutineType.eyeRest});

  setUp(() {
    // Before every fixture's fire time unless a test advances it.
    clock = FixedClock(DateTime.utc(2026, 10, 9, 7));
    gateway = InProcessNotificationGateway(clock);
  });

  test('tracks scheduled reminders by their planner id', () async {
    await gateway.schedule(water, exact: false);
    await gateway.schedule(eyes, exact: true);
    await gateway.schedule(water, exact: false);

    expect(await gateway.pendingIds(), {water.notificationId, eyes.notificationId});
    expect(
      await gateway.pendingReminders(),
      contains(PendingReminder(id: water.notificationId, payload: ReminderPayload.of(water))),
    );
  });

  test('cancel and cancelAll drop pending reminders', () async {
    await gateway.schedule(water, exact: false);
    await gateway.schedule(eyes, exact: false);
    await gateway.scheduleTest(at: DateTime.utc(2026, 10, 9, 11));
    expect(await gateway.pendingIds(), contains(kTestNotificationId));

    await gateway.cancel(water.notificationId);
    expect(await gateway.pendingIds(), {eyes.notificationId, kTestNotificationId});

    await gateway.cancelAll();
    expect(await gateway.pendingIds(), isEmpty);
  });

  test('desktop has no permission gates and no launch action', () async {
    await gateway.initialize(onForegroundAction: (_) {});
    expect(await gateway.requestPermission(), isTrue);
    expect(await gateway.notificationsEnabled(), isTrue);
    expect(await gateway.canScheduleExact(), isTrue);
    expect(await gateway.launchAction(), isNull);
  });

  group('due handling', () {
    final early = PlannedReminder(fireAt: DateTime.utc(2026, 10, 9, 8), types: const {RoutineType.stretch});

    test('takeDue removes and returns due entries ordered by time', () async {
      await gateway.schedule(eyes, exact: false);
      await gateway.schedule(water, exact: false);
      await gateway.schedule(early, exact: false);

      final due = gateway.takeDue(DateTime.utc(2026, 10, 9, 9));

      expect(due, [
        DueReminder(id: early.notificationId, reminder: early),
        DueReminder(id: water.notificationId, reminder: water),
      ]);
      expect(await gateway.pendingIds(), {eyes.notificationId});
      expect(gateway.takeDue(DateTime.utc(2026, 10, 9, 9)), isEmpty);
    });

    test('takeDue breaks ties by id', () async {
      final a = PlannedReminder(fireAt: DateTime.utc(2026, 10, 9, 9), types: const {RoutineType.eyeRest});
      await gateway.schedule(a, exact: false);
      await gateway.schedule(water, exact: false);
      final ids = gateway.takeDue(DateTime.utc(2026, 10, 9, 9)).map((d) => d.id).toList();
      expect(ids, [a.notificationId, water.notificationId]..sort());
    });

    test('nextFireAt is the earliest pending time', () async {
      expect(gateway.nextFireAt, isNull);
      await gateway.schedule(eyes, exact: false);
      await gateway.schedule(water, exact: false);
      expect(gateway.nextFireAt, water.fireAt);
      gateway.takeDue(water.fireAt);
      expect(gateway.nextFireAt, eyes.fireAt);
    });

    test('dispatchAction forwards to the latest callback', () async {
      final first = <ReminderAction>[];
      final second = <ReminderAction>[];
      final action = ReminderAction(
        kind: ReminderActionKind.done,
        types: const {RoutineType.hydration},
        scheduledAt: water.fireAt,
        notificationId: water.notificationId,
      );
      gateway.dispatchAction(action); // no callback yet: ignored
      await gateway.initialize(onForegroundAction: first.add);
      await gateway.initialize(onForegroundAction: second.add);
      gateway.dispatchAction(action);
      expect(first, isEmpty);
      expect(second, [action]);
    });

    test('due entries count as delivered: hidden from the diff, kept for takeDue', () async {
      await gateway.schedule(water, exact: false);
      await gateway.schedule(eyes, exact: false);
      clock.current = DateTime.utc(2026, 10, 9, 9, 0, 30); // water is due, not yet drained

      expect(await gateway.pendingIds(), {eyes.notificationId});
      expect(await gateway.pendingReminders(), [
        PendingReminder(id: eyes.notificationId, payload: ReminderPayload.of(eyes)),
      ]);

      await gateway.cancel(water.notificationId);
      await gateway.cancelAll();
      expect(await gateway.pendingIds(), isEmpty);
      expect(gateway.takeDue(clock.current), [DueReminder(id: water.notificationId, reminder: water)]);
    });
  });
}
