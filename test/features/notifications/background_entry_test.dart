import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/config/background_ids.dart';
import 'package:knight_rise/features/notifications/data/background_entry.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/notifications/domain/reminder_payload.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';

void main() {
  final fireAt = DateTime.utc(2026, 10, 5, 7, 30);
  late List<String> calls;
  late List<ReminderAction> handled;
  Error? bootstrapError;
  Error? handleError;

  setUp(() {
    calls = [];
    handled = [];
    bootstrapError = null;
    handleError = null;
  });

  Future<void> run(NotificationResponse r) => handleBackgroundResponse(
    r,
    bootstrap: () async {
      calls.add('bootstrap');
      if (bootstrapError != null) throw bootstrapError!;
    },
    handle: (a) async {
      calls.add('handle');
      handled.add(a);
      if (handleError != null) throw handleError!;
    },
  );

  String payload() => ReminderPayload(types: const {RoutineType.hydration}, fireAt: fireAt).encode();

  NotificationResponse response(String? actionId, String? payload, {int? nid, bool dismissed = false}) =>
      NotificationResponse(
        notificationResponseType: dismissed
            ? NotificationResponseType.notificationDismissed
            : (actionId == null || actionId.isEmpty
                  ? NotificationResponseType.selectedNotification
                  : NotificationResponseType.selectedNotificationAction),
        id: nid,
        actionId: actionId,
        payload: payload,
      );

  test('done: bootstraps once, then handles the mapped action', () async {
    await run(response(NotificationActionIds.done, payload(), nid: 42));
    expect(calls, ['bootstrap', 'handle']);
    expect(
      handled.single,
      ReminderAction(
        kind: ReminderActionKind.done,
        types: const {RoutineType.hydration},
        scheduledAt: fireAt,
        notificationId: 42,
      ),
    );
  });

  test('snooze: bootstraps once, then handles the mapped action', () async {
    await run(response(NotificationActionIds.snooze, payload(), nid: 7));
    expect(calls, ['bootstrap', 'handle']);
    expect(handled.single.kind, ReminderActionKind.snooze);
    expect(handled.single.types, {RoutineType.hydration});
    expect(handled.single.scheduledAt, fireAt);
    expect(handled.single.notificationId, 7);
  });

  test('open (plain tap) calls neither bootstrap nor handle', () async {
    await run(response(null, payload()));
    expect(calls, isEmpty);
  });

  test('bad payload calls neither', () async {
    await run(response(NotificationActionIds.done, 'junk'));
    await run(response(NotificationActionIds.done, null));
    expect(calls, isEmpty);
  });

  test('dismissed response is ignored', () async {
    await run(response(NotificationActionIds.done, payload(), dismissed: true));
    expect(calls, isEmpty);
  });

  test('unknown action id is ignored', () async {
    await run(response('mystery', payload()));
    expect(calls, isEmpty);
  });

  test('bootstrap failure is swallowed and handle is not called', () async {
    bootstrapError = StateError('boom');
    await run(response(NotificationActionIds.done, payload()));
    expect(calls, ['bootstrap']);
  });

  test('handle failure is swallowed', () async {
    handleError = StateError('boom');
    await run(response(NotificationActionIds.snooze, payload()));
    expect(calls, ['bootstrap', 'handle']);
  });
}
