import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:knight_rise/core/di/bootstrap_background.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/features/notifications/data/notification_response_mapper.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/handle_reminder_action.dart';

/// Entry point for `onDidReceiveBackgroundNotificationResponse`. Must stay a
/// top-level function with the entry-point pragma so it survives tree shaking
/// and can be invoked while the app is not running.
///
/// Android: action buttons declared with `showsUserInterface: false` (Done /
/// Snooze) are delivered to this headless isolate, even when the app is alive
/// in the foreground; the UI isolate callback is not used for them. This
/// isolate bootstraps its own DI and opens the database through Drift's shared
/// isolate server, so writes reach the UI isolate's streams. The UI's
/// `ScheduleSyncService` also reacts to the newly written event and
/// reconciles on its side.
///
/// iOS: actions without the foreground option wake the app in the background
/// and the plugin invokes this handler. The AppDelegate registers the plugin
/// registrant callback so plugins are available in the background engine.
///
/// Plain taps (`open`) are not handled here: opening the app is handled by the
/// UI isolate / launch details.
///
/// This function never throws: a failing background handler would otherwise
/// crash the headless isolate.
@pragma('vm:entry-point')
Future<void> knightNotificationBackgroundHandler(NotificationResponse response) {
  return handleBackgroundResponse(
    response,
    bootstrap: bootstrapBackground,
    handle: (a) => getIt<HandleReminderAction>()(a),
  );
}

/// Testable core of [knightNotificationBackgroundHandler].
///
/// Maps [response] to a [ReminderAction]; ignores unreadable payloads,
/// dismissals and `open`. Otherwise awaits [bootstrap] and then [handle].
/// Errors are logged and swallowed.
Future<void> handleBackgroundResponse(
  NotificationResponse response, {
  required Future<void> Function() bootstrap,
  required Future<void> Function(ReminderAction action) handle,
}) async {
  try {
    final action = reminderActionFromResponse(response);
    if (action == null || action.kind == ReminderActionKind.open) return;
    await bootstrap();
    await handle(action);
    // ignore: avoid_catches_without_on_clauses, a background handler must never throw.
  } catch (e, st) {
    debugPrint('Knight Rise: background notification action failed: $e\n$st');
  }
}
