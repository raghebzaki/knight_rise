import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/features/notifications/data/desktop_toast_codec.dart';
import 'package:knight_rise/features/notifications/data/desktop_toasts.dart';
import 'package:knight_rise/features/notifications/domain/due_reminder.dart';
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
/// It keeps the pending set so the reconciler's diff stays stable. The desktop
/// alarm clock drains due entries with [takeDue] and presents them; toast
/// buttons feed back through [dispatchAction].
///
/// An entry whose fire time has passed counts as delivered, like an OS
/// notification that already fired: [pendingIds], [pendingReminders],
/// [cancel] and [cancelAll] no longer see it, and it belongs to the alarm clock
/// until [takeDue] drains it. Otherwise a reconcile landing between the fire
/// time and the next heartbeat (a settings edit, or the resume right after
/// wake) would cancel it as stale before the catch-up rule ever saw it.
///
/// Registered (as both this class and [NotificationGateway], the same
/// instance) by the desktop module in `notifications_module.dart`.
class InProcessNotificationGateway implements NotificationGateway {
  InProcessNotificationGateway(this._clock, this._toasts);

  final Clock _clock;
  final DesktopToasts _toasts;
  Future<void>? _initFuture;
  final Map<int, PlannedReminder> _pending = {};
  void Function(ReminderAction action)? _onAction;

  /// Stores the callback that [dispatchAction] forwards to (latest wins) and
  /// starts the toast backend once.
  @override
  Future<void> initialize({required void Function(ReminderAction action) onForegroundAction}) {
    _onAction = onForegroundAction;
    return _initFuture ??= _toasts.initialize(_onToastResponse);
  }

  void _onToastResponse(NotificationResponse response) {
    final action = reminderActionFromDesktopResponse(response);
    if (action != null) dispatchAction(action);
  }

  /// Forwards a user action (toast Done / Snooze / body click) to the app.
  void dispatchAction(ReminderAction action) => _onAction?.call(action);

  /// Removes and returns every pending reminder whose fire time is not after
  /// [now], ordered by fire time then id.
  List<DueReminder> takeDue(DateTime now) {
    final due =
        [
          for (final MapEntry(:key, :value) in _pending.entries)
            if (!value.fireAt.isAfter(now)) DueReminder(id: key, reminder: value),
        ]..sort((a, b) {
          final byTime = a.reminder.fireAt.compareTo(b.reminder.fireAt);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
    for (final d in due) {
      _pending.remove(d.id);
    }
    return due;
  }

  /// Earliest fire time held (including due entries not yet drained), or null
  /// when nothing is held.
  DateTime? get nextFireAt {
    DateTime? earliest;
    for (final r in _pending.values) {
      if (earliest == null || r.fireAt.isBefore(earliest)) earliest = r.fireAt;
    }
    return earliest;
  }

  /// Entries not yet due, i.e. what the OS scheduler would still hold.
  Iterable<MapEntry<int, PlannedReminder>> get _upcoming {
    final now = _clock.now();
    return _pending.entries.where((e) => e.value.fireAt.isAfter(now));
  }

  @override
  Future<void> schedule(PlannedReminder reminder, {required bool exact}) async =>
      _pending[reminder.notificationId] = reminder;

  @override
  Future<void> scheduleTest({required DateTime at}) async =>
      _pending[kTestNotificationId] = PlannedReminder(fireAt: at, types: const {RoutineType.hydration});

  @override
  Future<void> cancel(int id) async {
    if (_pending[id]?.fireAt.isAfter(_clock.now()) ?? false) _pending.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    _upcoming.map((e) => e.key).toList().forEach(_pending.remove);
  }

  @override
  Future<Set<int>> pendingIds() async => {for (final e in _upcoming) e.key};

  @override
  Future<List<PendingReminder>> pendingReminders() async => [
    for (final MapEntry(:key, :value) in _upcoming) PendingReminder(id: key, payload: ReminderPayload.of(value)),
  ];

  /// Desktop shows Shield state in the app window, not a status notification.
  @override
  Future<void> showShieldStatus({required DateTime until}) async {}

  @override
  Future<void> clearShieldStatus() async {}

  @override
  Future<bool> requestPermission() => _toasts.requestPermission();

  @override
  Future<bool> notificationsEnabled() => _toasts.notificationsEnabled();

  /// Due times come from the app's own clock, so they are always exact.
  @override
  Future<bool> canScheduleExact() async => true;

  @override
  Future<void> requestExactAlarmPermission() async {}

  @override
  Future<ReminderAction?> launchAction() async {
    final response = await _toasts.launchResponse();
    return response == null ? null : reminderActionFromDesktopResponse(response);
  }
}
