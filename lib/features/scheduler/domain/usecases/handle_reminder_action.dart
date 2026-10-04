import 'package:injectable/injectable.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/services/schedule_reconciler.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';

/// Applies a notification action (Done / Snooze / tap). Shared by the
/// foreground callback and the background isolate handler.
@injectable
class HandleReminderAction {
  const HandleReminderAction(this._complete, this._snooze, this._reconciler);

  final CompleteRoutine _complete;
  final SnoozeRoutine _snooze;
  final ScheduleReconciler _reconciler;

  Future<void> call(ReminderAction action) async {
    // Stable order so event ids are deterministic for merged notifications.
    final types = action.types.toList()..sort((a, b) => a.index.compareTo(b.index));
    switch (action.kind) {
      case ReminderActionKind.done:
        for (final t in types) {
          await _complete(t, scheduledAt: action.scheduledAt);
        }
      case ReminderActionKind.snooze:
        for (final t in types) {
          // False means the max-snooze rule refused; nothing to do.
          await _snooze(t, scheduledAt: action.scheduledAt);
        }
      case ReminderActionKind.open:
        // Navigation is handled by the app layer.
        return;
    }
    await _reconciler.reconcile(ReconcileTrigger.action);
  }
}
