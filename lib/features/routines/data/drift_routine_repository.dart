import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/routines/domain/repositories/routine_repository.dart';

@LazySingleton(as: RoutineRepository)
class DriftRoutineRepository implements RoutineRepository {
  const DriftRoutineRepository(this._db);
  final AppDatabase _db;

  SimpleSelectStatement<$RoutinesTable, RoutineRow> get _query => _db.select(_db.routines);

  @override
  Stream<List<Routine>> watchAll() => _query.watch().map(_toDomain);

  @override
  Future<List<Routine>> getAll() => _query.get().then(_toDomain);

  @override
  Future<void> save(Routine r) => _db
      .into(_db.routines)
      .insertOnConflictUpdate(
        RoutinesCompanion.insert(
          type: r.type,
          intervalMinutes: r.intervalMinutes,
          dailyTarget: r.dailyTarget,
          enabled: Value(r.enabled),
          mode: r.mode,
        ),
      );

  static List<Routine> _toDomain(List<RoutineRow> rows) => [
    for (final row in rows)
      Routine(
        type: row.type,
        intervalMinutes: row.intervalMinutes,
        dailyTarget: row.dailyTarget,
        enabled: row.enabled,
        mode: row.mode,
      ),
  ]..sort((a, b) => a.type.index.compareTo(b.type.index));
}
