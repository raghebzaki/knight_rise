import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/repositories/reconcile_run_repository.dart';

@LazySingleton(as: ReconcileRunRepository)
class DriftReconcileRunRepository implements ReconcileRunRepository {
  const DriftReconcileRunRepository(this._db);
  final AppDatabase _db;

  @override
  Future<void> record(ReconcileRun r) => _db
      .into(_db.reconcileRuns)
      .insert(
        ReconcileRunsCompanion.insert(
          at: r.at,
          trigger: r.trigger.name,
          planned: r.planned,
          added: r.added,
          cancelled: r.cancelled,
          error: Value(r.error),
        ),
      );

  @override
  Stream<List<ReconcileRun>> watchRecent({int limit = 50}) =>
      (_db.select(_db.reconcileRuns)
            ..orderBy([(t) => OrderingTerm.desc(t.at), (t) => OrderingTerm.desc(t.id)])
            ..limit(limit))
          .watch()
          .map((rows) => rows.map(_toDomain).toList());

  @override
  Future<void> prune({int keep = 200}) async {
    final newest = _db.selectOnly(_db.reconcileRuns)
      ..addColumns([_db.reconcileRuns.id])
      ..orderBy([OrderingTerm.desc(_db.reconcileRuns.at), OrderingTerm.desc(_db.reconcileRuns.id)])
      ..limit(keep);
    await (_db.delete(_db.reconcileRuns)..where((t) => t.id.isNotInQuery(newest))).go();
  }

  static ReconcileRun _toDomain(ReconcileRunRow r) => ReconcileRun(
    at: r.at,
    trigger: ReconcileTrigger.values.asNameMap()[r.trigger] ?? ReconcileTrigger.periodic,
    planned: r.planned,
    added: r.added,
    cancelled: r.cancelled,
    error: r.error,
  );
}
