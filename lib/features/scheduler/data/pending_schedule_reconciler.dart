import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/repositories/reconcile_run_repository.dart';
import 'package:knight_rise/features/scheduler/domain/services/schedule_reconciler.dart';

/// Placeholder: only records an empty run so triggers are observable.
/// Replaced by the real planner-driven reconciler in Task 3.
@LazySingleton(as: ScheduleReconciler)
class PendingScheduleReconciler implements ScheduleReconciler {
  const PendingScheduleReconciler(this._runs, this._clock);
  final ReconcileRunRepository _runs;
  final Clock _clock;

  @override
  Future<ReconcileRun> reconcile(ReconcileTrigger trigger) async {
    final run = ReconcileRun(at: _clock.now(), trigger: trigger, planned: 0, added: 0, cancelled: 0);
    await _runs.record(run);
    return run;
  }
}
