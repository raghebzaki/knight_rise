import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/routines/domain/repositories/routine_repository.dart';

/// The routine list with inline on/off switches.
@injectable
class RoutinesCubit extends Cubit<List<Routine>?> {
  RoutinesCubit(this._repo) : super(null) {
    _sub = _repo.watchAll().listen(emit);
  }

  final RoutineRepository _repo;
  late final StreamSubscription<List<Routine>> _sub;

  Future<void> setEnabled(RoutineType type, {required bool enabled}) async {
    final routine = (await _repo.getAll()).where((r) => r.type == type).firstOrNull;
    if (routine == null) return;
    await _repo.save(routine.copyWith(enabled: enabled));
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    await super.close();
  }
}
