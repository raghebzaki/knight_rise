import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:knight_rise/core/config/background_ids.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/notifications/domain/reminder_payload.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';

/// Maps a plugin [NotificationResponse] to a [ReminderAction].
///
/// Returns null for dismissals, unknown action ids and unreadable payloads.
/// A null/empty action id is a plain tap on the notification body ("open").
ReminderAction? reminderActionFromResponse(NotificationResponse response) {
  if (response.notificationResponseType == NotificationResponseType.notificationDismissed) return null;
  final actionId = response.actionId;
  if (actionId == NotificationActionIds.endShield) {
    // The Shield status notification has no reminder payload. The action does
    // not depend on time, so a fixed epoch keeps the mapping deterministic.
    return ReminderAction(
      kind: ReminderActionKind.endShield,
      types: const {},
      scheduledAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      notificationId: response.id ?? kShieldStatusNotificationId,
    );
  }
  final payload = ReminderPayload.tryDecode(response.payload);
  if (payload == null) return null;
  final ReminderActionKind kind;
  if (actionId == null || actionId.isEmpty) {
    kind = ReminderActionKind.open;
  } else if (actionId == NotificationActionIds.done) {
    kind = ReminderActionKind.done;
  } else if (actionId == NotificationActionIds.snooze) {
    kind = ReminderActionKind.snooze;
  } else {
    return null;
  }
  return ReminderAction(
    kind: kind,
    types: payload.types,
    scheduledAt: payload.fireAt,
    // Same deterministic id the planner used when scheduling.
    notificationId: response.id ?? PlannedReminder(fireAt: payload.fireAt, types: payload.types).notificationId,
  );
}
