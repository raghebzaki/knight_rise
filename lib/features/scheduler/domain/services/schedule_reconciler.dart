import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';

/// Brings the OS notification schedule in line with the plan. Implementations
/// must record a [ReconcileRun] and return it.
abstract interface class ScheduleReconciler {
  Future<ReconcileRun> reconcile(ReconcileTrigger trigger);
}
