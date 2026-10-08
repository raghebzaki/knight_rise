import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/routines/domain/repositories/routine_repository.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';

class RoutineEditorState extends Equatable {
  const RoutineEditorState({this.saved, this.draft, this.waterPerTapMl = 250, this.saving = false});

  final Routine? saved;
  final Routine? draft;
  final int waterPerTapMl;
  final bool saving;

  bool get loaded => draft != null;
  bool get isDirty => draft != saved;
  bool get canSave => loaded && isDirty && !saving;

  RoutineEditorState copyWith({Routine? saved, Routine? draft, int? waterPerTapMl, bool? saving}) => RoutineEditorState(
    saved: saved ?? this.saved,
    draft: draft ?? this.draft,
    waterPerTapMl: waterPerTapMl ?? this.waterPerTapMl,
    saving: saving ?? this.saving,
  );

  @override
  List<Object?> get props => [saved, draft, waterPerTapMl, saving];
}

/// Editable draft of one routine; nothing is persisted until [save].
@injectable
class RoutineEditorCubit extends Cubit<RoutineEditorState> {
  RoutineEditorCubit(this._routines, this._settings, @factoryParam this.type) : super(const RoutineEditorState());

  static const int intervalStep = 5;
  static const int minTarget = 1;
  static const int maxTarget = 24;

  final RoutineRepository _routines;
  final SettingsRepository _settings;
  final RoutineType type;

  Future<void> load() async {
    final routine = (await _routines.getAll()).where((r) => r.type == type).firstOrNull;
    final settings = await _settings.get();
    if (isClosed || routine == null) return;
    emit(RoutineEditorState(saved: routine, draft: routine, waterPerTapMl: settings.waterPerTapMl));
  }

  void setEnabled({required bool enabled}) => _update((r) => r.copyWith(enabled: enabled));

  /// Clamps to [Routine.intervalRange] and snaps to [intervalStep] minutes.
  void setInterval(int minutes) {
    final range = Routine.intervalRange(type);
    final snapped = (minutes / intervalStep).round() * intervalStep;
    _update((r) => r.copyWith(intervalMinutes: snapped.clamp(range.min, range.max)));
  }

  void setTarget(int count) => _update((r) => r.copyWith(dailyTarget: count.clamp(minTarget, maxTarget)));

  void incrementTarget() => _update((r) => r.copyWith(dailyTarget: (r.dailyTarget + 1).clamp(minTarget, maxTarget)));

  void decrementTarget() => _update((r) => r.copyWith(dailyTarget: (r.dailyTarget - 1).clamp(minTarget, maxTarget)));

  void setMode(ScheduleMode mode) => _update((r) => r.copyWith(mode: mode));

  void _update(Routine Function(Routine) change) {
    final draft = state.draft;
    if (draft == null) return;
    emit(state.copyWith(draft: change(draft)));
  }

  Future<bool> save() async {
    final draft = state.draft;
    if (!state.canSave || draft == null) return false;
    emit(state.copyWith(saving: true));
    try {
      await _routines.save(draft);
    } on Object {
      if (!isClosed) emit(state.copyWith(saving: false));
      rethrow;
    }
    if (!isClosed) emit(state.copyWith(saved: draft, saving: false));
    return true;
  }
}
