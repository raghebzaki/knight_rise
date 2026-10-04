import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';

abstract interface class ReconcileRunRepository {
  Future<void> record(ReconcileRun run);

  /// Newest first, at most [limit] entries. Emits again on every write.
  Stream<List<ReconcileRun>> watchRecent({int limit = 50});

  /// Deletes everything except the newest [keep] runs.
  Future<void> prune({int keep = 200});
}
