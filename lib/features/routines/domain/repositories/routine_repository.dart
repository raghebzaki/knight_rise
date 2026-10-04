import 'package:knight_rise/features/routines/domain/entities/routine.dart';

abstract interface class RoutineRepository {
  /// All routines, ordered by [RoutineType] index.
  Stream<List<Routine>> watchAll();

  Future<List<Routine>> getAll();

  Future<void> save(Routine routine);
}
