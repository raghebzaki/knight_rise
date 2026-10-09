import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:knight_rise/features/notifications/data/notification_response_mapper.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';

const String _separator = '|';

/// Packs the action into the toast activation argument as `actionId|payload`.
///
/// [actionId] is `''` for a body click, or `NotificationActionIds.done` /
/// `.snooze`. Windows hands the argument back as both payload and action id,
/// so the action has to travel inside it. A reminder payload (JSON from
/// `ReminderPayload.encode`) never contains `|`.
String encodeToastArgument(String actionId, String payload) => '$actionId$_separator$payload';

/// Maps a desktop toast [response] to a [ReminderAction].
///
/// Windows reports the whole argument as both `payload` and `actionId`; the
/// action is read from the argument. macOS reports the original payload and,
/// for an action button, its real id (a body tap has none). Returns null for
/// dismissals, unknown actions and unreadable payloads.
ReminderAction? reminderActionFromDesktopResponse(NotificationResponse response) {
  final raw = response.payload ?? '';
  final cut = raw.indexOf(_separator);
  final argAction = cut < 0 ? '' : raw.substring(0, cut);
  final payloadJson = cut < 0 ? raw : raw.substring(cut + 1);
  final reported = response.actionId;
  final effective = reported != null && reported.isNotEmpty && reported != response.payload ? reported : argAction;
  return reminderActionFromResponse(
    NotificationResponse(
      notificationResponseType: response.notificationResponseType,
      id: response.id,
      actionId: effective.isEmpty ? null : effective,
      payload: payloadJson,
    ),
  );
}
