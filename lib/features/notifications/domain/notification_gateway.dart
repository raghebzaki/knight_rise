import 'package:knight_rise/features/notifications/domain/pending_reminder.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';

/// Notification ids below this value are reserved for diagnostics (see
/// [kTestNotificationId]). Planner ids are minute-derived and far larger, and
/// the reconciler's diff path never cancels a reserved id.
const int kReservedNotificationIdLimit = 1000;

/// Id used by [NotificationGateway.scheduleTest].
const int kTestNotificationId = 1;

/// Id of the ongoing Shield status notification (Android). Reserved range, so
/// the reconciler's diff path never cancels it as "stale".
const int kShieldStatusNotificationId = 2;

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

  /// Pending notifications with their decoded payloads (dev diagnostics).
  /// [PendingReminder.payload] is null for notifications we did not create
  /// or whose payload is unreadable.
  Future<List<PendingReminder>> pendingReminders();

  /// Schedules a hydration test notification at [at] under the fixed id
  /// [kTestNotificationId], with the same content as a real reminder and
  /// inexact timing (dev diagnostics). Replaces any earlier test notification.
  Future<void> scheduleTest({required DateTime at});

  /// Shows (or refreshes) the ongoing "Shield active" status notification under
  /// [kShieldStatusNotificationId], counting down to [until]. It also expires
  /// by itself at [until]. No-op on iOS (status lives in the app).
  Future<void> showShieldStatus({required DateTime until});

  /// Removes the Shield status notification. No-op when none is shown / on iOS.
  Future<void> clearShieldStatus();

  /// Android 13+/iOS permission prompt. Returns granted.
  Future<bool> requestPermission();

  /// Whether the user currently allows notifications from this app (Android:
  /// notifications enabled for the app, incl. `POST_NOTIFICATIONS`; iOS:
  /// authorized). True on platforms without a notification permission.
  Future<bool> notificationsEnabled();

  /// Whether exact alarms are currently allowed (Android 12+); true on iOS.
  Future<bool> canScheduleExact();

  /// Android 12+: opens the system "Alarms & reminders" screen so the user can
  /// allow exact alarms. No-op elsewhere. The result is read via
  /// [canScheduleExact] once the user returns.
  Future<void> requestExactAlarmPermission();

  /// Action that launched the app from a notification tap, if any.
  Future<ReminderAction?> launchAction();
}
