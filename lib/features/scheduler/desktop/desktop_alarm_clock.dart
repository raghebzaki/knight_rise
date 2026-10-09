import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/features/notifications/data/in_process_notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/due_reminder.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/reminder_presenter.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';

/// Desktop stand-in for the OS alarm scheduler: on every [tick] it takes the
/// reminders that are due from the in-process gateway and presents them.
///
/// Catch-up rule: after sleep or a stalled process many reminders can be
/// overdue at once, and a burst of stale toasts is noise. A due reminder is
/// *fresh* when it is at most [catchUpGrace] overdue, otherwise *stale*.
/// Stale ones are dropped silently (they become "missed" through the normal
/// day-rollover derivation; nothing is written). The diagnostics test
/// notification is presented on its own when fresh. All fresh planner
/// reminders collapse into ONE presentation: a single one as is, several as a
/// merged reminder (latest fire time, union of types, recovery only if every
/// member is recovery).
@desktopEnv
@lazySingleton
class DesktopAlarmClock {
  DesktopAlarmClock(this._gateway, this._presenter, this._clock);

  /// How overdue a reminder may be and still be shown.
  static const Duration catchUpGrace = Duration(minutes: 10);

  final InProcessNotificationGateway _gateway;
  final ReminderPresenter _presenter;
  final Clock _clock;

  /// Earliest pending fire time (for the tray).
  DateTime? get nextFireAt => _gateway.nextFireAt;

  /// Presents what is due now. Never throws.
  Future<void> tick() async {
    try {
      final now = _clock.now();
      final due = _gateway.takeDue(now);
      if (due.isEmpty) return;
      final fresh = <DueReminder>[];
      var stale = 0;
      for (final d in due) {
        if (now.difference(d.reminder.fireAt) <= catchUpGrace) {
          fresh.add(d);
        } else {
          stale++;
        }
      }
      if (stale > 0) debugPrint('[alarm] dropped $stale stale reminder(s)');
      final test = fresh.where((d) => d.id == kTestNotificationId).toList();
      final planned = fresh.where((d) => d.id != kTestNotificationId).toList();
      for (final t in test) {
        await _present(t);
      }
      if (planned.isEmpty) return;
      await _present(planned.length == 1 ? planned.single : _merge(planned));
    } on Object catch (e, st) {
      debugPrint('[alarm] tick failed: $e\n$st');
    }
  }

  static DueReminder _merge(List<DueReminder> due) {
    final merged = PlannedReminder(
      fireAt: due.map((d) => d.reminder.fireAt).reduce((a, b) => a.isAfter(b) ? a : b),
      types: {for (final d in due) ...d.reminder.types},
      recovery: due.every((d) => d.reminder.recovery),
    );
    return DueReminder(id: merged.notificationId, reminder: merged);
  }

  Future<void> _present(DueReminder due) async {
    try {
      await _presenter.present(due);
    } on Object catch (e, st) {
      debugPrint('[alarm] presenting ${due.id} failed: $e\n$st');
    }
  }
}
