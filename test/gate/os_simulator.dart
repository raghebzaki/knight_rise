import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/pending_reminder.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/notifications/domain/reminder_payload.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';

/// A [NotificationGateway] that behaves like the real OS scheduler plus
/// `flutter_local_notifications`:
///
/// * [schedule] adds a pending notification or replaces the one with the same
///   id; a fire time that is not in the future throws (the plugin rejects it).
/// * [cancel] removes one id, [cancelAll] removes every pending id (the plugin's
///   `cancelAllPendingNotifications`), including the reserved diagnostics id.
/// * [advanceTo] moves the shared [clock] and "delivers" every pending
///   notification that is due: it leaves the pending set and lands in
///   [delivered].
/// * The Shield status notification (id 2) is shown with `show`, so it is not
///   part of the pending set and survives [cancelAll]. Like the real gateway,
///   showing a status that already ended clears it instead. It does not expire
///   by itself in this model, so tests prove that a reconcile clears it.
class OsNotificationSimulator implements NotificationGateway {
  OsNotificationSimulator(this.clock);

  final FixedClock clock;

  final Map<int, _Pending> _pending = {};

  /// Reminders the OS has fired, in delivery order.
  final List<PlannedReminder> delivered = [];

  /// Diagnostics test notifications the OS has fired.
  int deliveredTests = 0;

  /// Every id passed to [cancel], in call order.
  final List<int> cancelledIds = [];
  int cancelAllCalls = 0;

  /// `until` of the visible Shield status notification; null when none is shown.
  DateTime? shieldStatusUntil;
  int showShieldStatusCalls = 0;
  int clearShieldStatusCalls = 0;

  bool get shieldStatusShown => shieldStatusUntil != null;

  @override
  Future<void> initialize({required void Function(ReminderAction action) onForegroundAction}) async {}

  @override
  Future<void> schedule(PlannedReminder reminder, {required bool exact}) async {
    _put(reminder.notificationId, reminder.fireAt, reminder);
  }

  @override
  Future<void> scheduleTest({required DateTime at}) async => _put(kTestNotificationId, at, null);

  void _put(int id, DateTime fireAt, PlannedReminder? reminder) {
    if (!fireAt.isAfter(clock.now())) {
      throw ArgumentError.value(fireAt, 'scheduledDate', 'Must be a date in the future (now ${clock.now()})');
    }
    _pending[id] = _Pending(fireAt, reminder);
  }

  @override
  Future<void> cancel(int id) async {
    cancelledIds.add(id);
    _pending.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    _pending.clear();
  }

  @override
  Future<Set<int>> pendingIds() async => {..._pending.keys};

  @override
  Future<List<PendingReminder>> pendingReminders() async {
    final entries = _pending.entries.toList()..sort((a, b) => a.value.fireAt.compareTo(b.value.fireAt));
    return [
      for (final MapEntry(key: id, value: p) in entries)
        PendingReminder(id: id, payload: p.reminder == null ? null : ReminderPayload.of(p.reminder!)),
    ];
  }

  /// Moves the clock to [t] and fires everything due (`fireAt <= t`) in time order.
  void advanceTo(DateTime t) {
    assert(!t.isBefore(clock.now()), 'Time only moves forward: $t < ${clock.now()}');
    clock.current = t;
    fireDue(t);
  }

  /// Delivers (removes from pending) every reminder with `fireAt <= now`, in
  /// time order, and returns them. Does not move the clock.
  List<PlannedReminder> fireDue(DateTime now) {
    final due = _pending.entries.where((e) => !e.value.fireAt.isAfter(now)).toList()
      ..sort((a, b) => a.value.fireAt.compareTo(b.value.fireAt));
    final fired = <PlannedReminder>[];
    for (final MapEntry(key: id, value: p) in due) {
      _pending.remove(id);
      final r = p.reminder;
      if (r == null) {
        deliveredTests++;
      } else {
        delivered.add(r);
        fired.add(r);
      }
    }
    return fired;
  }

  @override
  Future<void> showShieldStatus({required DateTime until}) async {
    if (!until.isAfter(clock.now())) {
      await clearShieldStatus();
      return;
    }
    showShieldStatusCalls++;
    shieldStatusUntil = until;
  }

  @override
  Future<void> clearShieldStatus() async {
    clearShieldStatusCalls++;
    shieldStatusUntil = null;
  }

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> notificationsEnabled() async => true;

  @override
  Future<bool> canScheduleExact() async => true;

  @override
  Future<void> requestExactAlarmPermission() async {}

  @override
  Future<ReminderAction?> launchAction() async => null;
}

class _Pending {
  _Pending(this.fireAt, this.reminder);

  final DateTime fireAt;

  /// Null for the diagnostics test notification.
  final PlannedReminder? reminder;
}
