import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/pending_reminder.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/notifications/domain/reminder_payload.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';

/// macOS / Windows: reminders are held by the running app, not the OS
/// scheduler. The app process keeps the pending set and builds each toast when
/// it is due, so its copy is in the language chosen at that moment and its
/// actions return to the live app (no background isolate).
///
/// Batch D0 seam: keeps the pending set so the reconciler's diff stays stable,
/// but does not show toasts yet; firing arrives with the desktop notifier.
@desktopEnv
@LazySingleton(as: NotificationGateway)
class InProcessNotificationGateway implements NotificationGateway {
  final Map<int, ReminderPayload> _pending = {};

  @override
  Future<void> initialize({required void Function(ReminderAction action) onForegroundAction}) async {}

  @override
  Future<void> schedule(PlannedReminder reminder, {required bool exact}) async =>
      _pending[reminder.notificationId] = ReminderPayload.of(reminder);

  @override
  Future<void> scheduleTest({required DateTime at}) async => _pending[kTestNotificationId] = ReminderPayload.of(
    PlannedReminder(fireAt: at, types: const {RoutineType.hydration}),
  );

  @override
  Future<void> cancel(int id) async => _pending.remove(id);

  @override
  Future<void> cancelAll() async => _pending.clear();

  @override
  Future<Set<int>> pendingIds() async => _pending.keys.toSet();

  @override
  Future<List<PendingReminder>> pendingReminders() async => [
    for (final MapEntry(:key, :value) in _pending.entries) PendingReminder(id: key, payload: value),
  ];

  /// Desktop shows Shield state in the app window, not a status notification.
  @override
  Future<void> showShieldStatus({required DateTime until}) async {}

  @override
  Future<void> clearShieldStatus() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> notificationsEnabled() async => true;

  /// Due times come from the app's own clock, so they are always exact.
  @override
  Future<bool> canScheduleExact() async => true;

  @override
  Future<void> requestExactAlarmPermission() async {}

  @override
  Future<ReminderAction?> launchAction() async => null;
}
