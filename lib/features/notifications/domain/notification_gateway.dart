import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';

/// Port to the OS notification scheduler.
abstract interface class NotificationGateway {
  /// Channels, iOS categories, foreground tap/action callback. Idempotent.
  Future<void> initialize({required void Function(ReminderAction action) onForegroundAction});

  /// Schedules [reminder]. The caller decides [exact] (see [canScheduleExact]);
  /// the gateway does not re-check the permission per call.
  Future<void> schedule(PlannedReminder reminder, {required bool exact});

  Future<void> cancel(int id);

  Future<void> cancelAll();

  /// IDs of notifications currently pending in the OS.
  Future<Set<int>> pendingIds();

  /// Android 13+/iOS permission prompt. Returns granted.
  Future<bool> requestPermission();

  /// Whether exact alarms are currently allowed (Android 12+); true on iOS.
  Future<bool> canScheduleExact();

  /// Action that launched the app from a notification tap, if any.
  Future<ReminderAction?> launchAction();
}
