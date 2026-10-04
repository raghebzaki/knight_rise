import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:knight_rise/features/notifications/data/notification_response_mapper.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';

/// Hook invoked by [knightNotificationBackgroundHandler] in the background isolate.
///
/// Task 4 assigns the real implementation (bootstrap background DI, then run
/// the Done / Snooze use cases and reconcile). It is `null` until then, which
/// makes background actions a safe no-op. Note that this is isolate-local
/// state: the background isolate starts fresh, so the assignment must happen
/// inside that isolate (e.g. in the handler path / `bootstrapBackground()`),
/// not in `main()` of the UI isolate.
Future<void> Function(ReminderAction action)? backgroundActionHandler;

/// Entry point for `onDidReceiveBackgroundNotificationResponse`. Must stay a
/// top-level function with the entry-point pragma so it survives tree shaking
/// and can be invoked while the app is not running.
@pragma('vm:entry-point')
Future<void> knightNotificationBackgroundHandler(NotificationResponse response) async {
  final action = reminderActionFromResponse(response);
  if (action == null) return;
  final handler = backgroundActionHandler;
  if (handler == null) {
    debugPrint('Knight Rise: no background handler set, ignoring ${action.kind.name}');
    return;
  }
  await handler(action);
}
