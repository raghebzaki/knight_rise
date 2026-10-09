import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/notifications/data/in_process_notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/pending_reminder.dart';
import 'package:knight_rise/features/notifications/domain/reminder_payload.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';

void main() {
  late InProcessNotificationGateway gateway;
  final water = PlannedReminder(fireAt: DateTime.utc(2026, 10, 9, 9), types: const {RoutineType.hydration});
  final eyes = PlannedReminder(fireAt: DateTime.utc(2026, 10, 9, 10), types: const {RoutineType.eyeRest});

  setUp(() => gateway = InProcessNotificationGateway());

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
}
