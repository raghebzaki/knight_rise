import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/config/background_ids.dart';
import 'package:knight_rise/features/notifications/data/desktop_toast_codec.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/notifications/domain/reminder_payload.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';

void main() {
  final payload = ReminderPayload(
    types: const {RoutineType.hydration, RoutineType.eyeRest},
    fireAt: DateTime.utc(2026, 10, 9, 9),
  ).encode();
  const types = {RoutineType.hydration, RoutineType.eyeRest};

  test('payload JSON never contains the separator', () {
    expect(payload, isNot(contains('|')));
  });

  test('encodes action then payload', () {
    expect(encodeToastArgument('', payload), '|$payload');
    expect(encodeToastArgument(NotificationActionIds.done, payload), 'done|$payload');
  });

  group('Windows-shaped responses (payload == actionId == argument)', () {
    ReminderAction? map(String action, {NotificationResponseType? type}) {
      final arg = encodeToastArgument(action, payload);
      return reminderActionFromDesktopResponse(
        NotificationResponse(
          notificationResponseType: type ?? NotificationResponseType.selectedNotification,
          actionId: arg,
          payload: arg,
        ),
      );
    }

    test('body click opens', () {
      final a = map('');
      expect(a?.kind, ReminderActionKind.open);
      expect(a?.types, types);
      expect(a?.scheduledAt, DateTime.utc(2026, 10, 9, 9));
    });

    test('Done and Snooze buttons', () {
      expect(map('done')?.kind, ReminderActionKind.done);
      expect(map('snooze')?.kind, ReminderActionKind.snooze);
    });

    test('unknown action and dismissal map to null', () {
      expect(map('bogus'), isNull);
      expect(map('done', type: NotificationResponseType.notificationDismissed), isNull);
    });
  });

  group('macOS-shaped responses', () {
    test('body tap: no action id, payload as shown', () {
      final a = reminderActionFromDesktopResponse(
        NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotification,
          id: 42,
          payload: encodeToastArgument('', payload),
        ),
      );
      expect(a?.kind, ReminderActionKind.open);
      expect(a?.notificationId, 42);
    });

    test('action button: real id wins over the argument', () {
      for (final (id, kind) in [
        (NotificationActionIds.done, ReminderActionKind.done),
        (NotificationActionIds.snooze, ReminderActionKind.snooze),
      ]) {
        final a = reminderActionFromDesktopResponse(
          NotificationResponse(
            notificationResponseType: NotificationResponseType.selectedNotificationAction,
            id: 7,
            actionId: id,
            payload: encodeToastArgument('', payload),
          ),
        );
        expect(a?.kind, kind);
        expect(a?.notificationId, 7);
        expect(a?.types, types);
      }
    });

    test('empty action id counts as a body tap', () {
      final a = reminderActionFromDesktopResponse(
        NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotification,
          actionId: '',
          payload: encodeToastArgument('', payload),
        ),
      );
      expect(a?.kind, ReminderActionKind.open);
    });
  });

  test('a bare JSON payload (no separator) is treated as a body click', () {
    final a = reminderActionFromDesktopResponse(
      NotificationResponse(notificationResponseType: NotificationResponseType.selectedNotification, payload: payload),
    );
    expect(a?.kind, ReminderActionKind.open);
  });

  test('garbage maps to null', () {
    for (final raw in [null, '', '|', 'done|', 'done|not json', '|{"v":9}', 'garbage']) {
      expect(
        reminderActionFromDesktopResponse(
          NotificationResponse(notificationResponseType: NotificationResponseType.selectedNotification, payload: raw),
        ),
        isNull,
        reason: '$raw',
      );
    }
  });
}
