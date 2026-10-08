import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/core/time/location_provider.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/routines/domain/repositories/routine_repository.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/repositories/reconcile_run_repository.dart';
import 'package:knight_rise/features/scheduler/domain/repositories/reminder_event_repository.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/scheduler/domain/services/schedule_reconciler.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';
import 'package:knight_rise/features/shield/domain/repositories/shield_repository.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/day_override_repository.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/work_schedule_repository.dart';

/// Triggers whose reason may have invalidated every pending notification
/// (content, zone or OS state), so the OS schedule is rebuilt from scratch.
const Set<ReconcileTrigger> _fullReplaceTriggers = {
  ReconcileTrigger.configChange,
  ReconcileTrigger.timezoneChange,
  ReconcileTrigger.boot,
};

/// Brings the OS notification schedule in line with [ReminderPlanner]'s plan.
///
/// Full-replace triggers cancel everything and schedule the whole plan; all
/// other triggers diff by deterministic notification id (cancel stale, add
/// missing, leave the rest). The diff path never cancels ids below
/// [kReservedNotificationIdLimit]: those are reserved for the diagnostics test
/// notification, which the plan knows nothing about. Full-replace triggers
/// (`cancelAll`) still clear it.
///
/// Concurrency: the UI and background isolates may reconcile at nearly the
/// same time. That is acceptable because the diff is idempotent: both compute
/// the same desired id set, and re-scheduling an id replaces the existing OS
/// notification. The worst case is redundant work, never duplicates.
///
/// Never writes ReminderEvents (missed reminders are derived at day rollover
/// in Milestone 4, and writing events would re-trigger the sync service).
/// Never throws: failures are recorded in the returned [ReconcileRun].
@LazySingleton(as: ScheduleReconciler)
class ReconcileSchedule implements ScheduleReconciler {
  const ReconcileSchedule(
    this._routines,
    this._workSchedule,
    this._settings,
    this._events,
    this._shields,
    this._overrides,
    this._runs,
    this._gateway,
    this._planner,
    this._clock,
    this._locationProvider,
  );

  final RoutineRepository _routines;
  final WorkScheduleRepository _workSchedule;
  final SettingsRepository _settings;
  final ReminderEventRepository _events;
  final ShieldRepository _shields;
  final DayOverrideRepository _overrides;
  final ReconcileRunRepository _runs;
  final NotificationGateway _gateway;
  final ReminderPlanner _planner;
  final Clock _clock;
  final LocationProvider _locationProvider;

  @override
  Future<ReconcileRun> reconcile(ReconcileTrigger trigger) async {
    final now = _clock.now();
    var planned = 0;
    var added = 0;
    var cancelled = 0;
    String? error;
    try {
      final location = _locationProvider.current;
      final routines = await _routines.getAll();
      final schedule = await _workSchedule.get();
      final settings = await _settings.get();
      final dayStart = startOfLocalDay(now, location);
      final today = await _events.getSince(dayStart);
      final shields = await _shields.getSince(dayStart);
      final overrides = await _overrides.getFrom(localDateOf(now, location));

      final plan = _planner.plan(
        PlannerInput(
          routines: routines,
          schedule: schedule,
          location: location,
          now: now,
          history: historyFromEvents(today),
          shields: [for (final s in shields) s.toWindow()],
          recoverOnExit: settings.shieldRecoverOnExit,
          overrides: overrides,
        ),
      );
      planned = plan.length;

      // Evaluated once per run; the gateway no longer re-checks per call.
      final exact = settings.precisionTiming && await _gateway.canScheduleExact();
      final pending = await _gateway.pendingIds();

      if (_fullReplaceTriggers.contains(trigger)) {
        await _gateway.cancelAll();
        cancelled = pending.length;
        for (final r in plan) {
          await _gateway.schedule(r, exact: exact);
          added++;
        }
      } else {
        final desired = {for (final r in plan) r.notificationId};
        for (final id in pending.difference(desired).where((id) => id >= kReservedNotificationIdLimit)) {
          await _gateway.cancel(id);
          cancelled++;
        }
        for (final r in plan) {
          if (pending.contains(r.notificationId)) continue;
          await _gateway.schedule(r, exact: exact);
          added++;
        }
      }
    } on Object catch (e) {
      error = e.toString();
    }

    await _syncShieldStatus(now);

    final run = ReconcileRun(
      at: now,
      trigger: trigger,
      planned: planned,
      added: added,
      cancelled: cancelled,
      error: error,
    );
    try {
      await _runs.record(run);
      await _runs.prune(); // default keeps the newest 200
    } on Object {
      // Audit-log failures must not break the reconcile contract.
    }
    return run;
  }

  /// Keeps the ongoing Shield status notification consistent with the stored
  /// Shield, on every trigger and in every isolate. Deliberately outside the
  /// plan's try block and never throws: a status-notification failure must not
  /// fail (or be recorded as an error of) an otherwise good reconcile.
  Future<void> _syncShieldStatus(DateTime now) async {
    try {
      final active = await _shields.active(now);
      if (active != null) {
        await _gateway.showShieldStatus(until: active.effectiveEnd);
      } else {
        await _gateway.clearShieldStatus();
      }
    } on Object {
      // Best effort; the next reconcile retries.
    }
  }
}
