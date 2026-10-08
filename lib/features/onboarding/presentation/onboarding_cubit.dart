import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/routines/domain/repositories/routine_repository.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/services/schedule_reconciler.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/work_schedule_repository.dart';
import 'package:knight_rise/features/work_hours/domain/work_schedule_validation.dart';
import 'package:knight_rise/features/work_hours/domain/work_week.dart';

enum OnboardingStep { welcome, routines, workHours, oath }

enum WorkDaysPreset { sunThu, monFri, custom }

/// Why the work-hours step cannot continue; null when it can.
enum WorkHoursProblem { noDays, endNotAfterStart, tooShort }

const Set<int> _sunThu = {DateTime.sunday, DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday};
const Set<int> _monFri = {DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday, DateTime.friday};

class OnboardingState extends Equatable {
  const OnboardingState({
    this.loaded = false,
    this.step = OnboardingStep.welcome,
    this.routines = const [],
    this.preset = WorkDaysPreset.sunThu,
    this.days = _sunThu,
    this.startMinute = 9 * 60,
    this.endMinute = 17 * 60,
    this.finishing = false,
    this.finishFailed = false,
  });

  final bool loaded;
  final OnboardingStep step;

  /// Draft routines, ordered by [RoutineType].
  final List<Routine> routines;
  final WorkDaysPreset preset;

  /// ISO weekdays that are work days.
  final Set<int> days;
  final int startMinute;
  final int endMinute;
  final bool finishing;
  final bool finishFailed;

  Routine? routine(RoutineType type) => routines.where((r) => r.type == type).firstOrNull;

  bool get hasEnabledRoutine => routines.any((r) => r.enabled);

  WorkHoursProblem? get workHoursProblem {
    if (days.isEmpty) return WorkHoursProblem.noDays;
    if (endMinute <= startMinute) return WorkHoursProblem.endNotAfterStart;
    final issues = validateWorkSchedule(schedule);
    if (issues.isEmpty) return null;
    return switch (issues.first.type) {
      WorkScheduleIssueType.endNotAfterStart => WorkHoursProblem.endNotAfterStart,
      _ => WorkHoursProblem.tooShort,
    };
  }

  /// What would be saved. Only meaningful when [endMinute] is after
  /// [startMinute] (otherwise an empty schedule, as [TimeWindow] forbids it).
  WorkSchedule get schedule => endMinute <= startMinute
      ? const WorkSchedule()
      : WorkSchedule(
          days: {
            for (final d in weekdaysSundayFirst)
              if (days.contains(d)) d: [TimeWindow(startMinute: startMinute, endMinute: endMinute)],
          },
        );

  bool get isValid => loaded && hasEnabledRoutine && workHoursProblem == null;

  /// Whether Next may leave the current step.
  bool get canAdvance => switch (step) {
    OnboardingStep.welcome => loaded,
    OnboardingStep.routines => hasEnabledRoutine,
    OnboardingStep.workHours => workHoursProblem == null,
    OnboardingStep.oath => false,
  };

  OnboardingState copyWith({
    bool? loaded,
    OnboardingStep? step,
    List<Routine>? routines,
    WorkDaysPreset? preset,
    Set<int>? days,
    int? startMinute,
    int? endMinute,
    bool? finishing,
    bool? finishFailed,
  }) => OnboardingState(
    loaded: loaded ?? this.loaded,
    step: step ?? this.step,
    routines: routines ?? this.routines,
    preset: preset ?? this.preset,
    days: days ?? this.days,
    startMinute: startMinute ?? this.startMinute,
    endMinute: endMinute ?? this.endMinute,
    finishing: finishing ?? this.finishing,
    finishFailed: finishFailed ?? this.finishFailed,
  );

  @override
  List<Object?> get props => [loaded, step, routines, preset, days, startMinute, endMinute, finishing, finishFailed];
}

/// Draft of the first-run setup. Nothing is persisted until [finish].
@injectable
class OnboardingCubit extends Cubit<OnboardingState> {
  OnboardingCubit(this._routines, this._schedule, this._settings, this._reconciler) : super(const OnboardingState());

  final RoutineRepository _routines;
  final WorkScheduleRepository _schedule;
  final SettingsRepository _settings;
  final ScheduleReconciler _reconciler;

  /// Interval choices offered per routine (all inside [Routine.intervalRange]).
  static List<int> intervalOptions(RoutineType type) => switch (type) {
    RoutineType.hydration => const [30, 45, 60, 90],
    RoutineType.stretch => const [30, 45, 60, 90],
    RoutineType.eyeRest => const [15, 20, 30, 45],
  };

  /// Seeds the draft from the stored routines and work hours.
  Future<void> load() async {
    final routines = [...await _routines.getAll()]..sort((a, b) => a.type.index.compareTo(b.type.index));
    final stored = await _schedule.get();
    if (isClosed) return;
    var next = OnboardingState(loaded: true, routines: routines);
    final uniform = uniformSchedule(stored);
    if (uniform != null && uniform.days.isNotEmpty && uniform.windows.length == 1) {
      final w = uniform.windows.single;
      final days = uniform.days.toSet();
      next = next.copyWith(
        days: days,
        startMinute: w.startMinute,
        endMinute: w.endMinute,
        preset: setEquals(days, _sunThu)
            ? WorkDaysPreset.sunThu
            : setEquals(days, _monFri)
            ? WorkDaysPreset.monFri
            : WorkDaysPreset.custom,
      );
    }
    emit(next);
  }

  void next() {
    if (!state.canAdvance) return;
    emit(state.copyWith(step: OnboardingStep.values[state.step.index + 1]));
  }

  void back() {
    if (state.step == OnboardingStep.welcome || state.finishing) return;
    emit(state.copyWith(step: OnboardingStep.values[state.step.index - 1]));
  }

  void setRoutineEnabled(RoutineType type, {required bool enabled}) =>
      _updateRoutine(type, (r) => r.copyWith(enabled: enabled));

  void setInterval(RoutineType type, int minutes) {
    final range = Routine.intervalRange(type);
    if (minutes < range.min || minutes > range.max) return;
    _updateRoutine(type, (r) => r.copyWith(intervalMinutes: minutes));
  }

  void _updateRoutine(RoutineType type, Routine Function(Routine) update) {
    if (state.routine(type) == null) return;
    emit(
      state.copyWith(
        routines: [
          for (final r in state.routines)
            if (r.type == type) update(r) else r,
        ],
      ),
    );
  }

  void setPreset(WorkDaysPreset preset) => switch (preset) {
    WorkDaysPreset.sunThu => emit(state.copyWith(preset: preset, days: _sunThu)),
    WorkDaysPreset.monFri => emit(state.copyWith(preset: preset, days: _monFri)),
    // Keeps the days chosen so far as the starting point.
    WorkDaysPreset.custom => emit(state.copyWith(preset: preset)),
  };

  /// Toggles [weekday] (ISO). Only effective in the custom preset.
  void toggleDay(int weekday) {
    if (state.preset != WorkDaysPreset.custom || !weekdaysSundayFirst.contains(weekday)) return;
    final days = {...state.days};
    if (!days.remove(weekday)) days.add(weekday);
    emit(state.copyWith(days: days));
  }

  void setStart(int minute) => emit(state.copyWith(startMinute: minute.clamp(0, 1439)));

  void setEnd(int minute) => emit(state.copyWith(endMinute: minute.clamp(1, 1440)));

  /// Saves everything, marks onboarding completed (which makes the router
  /// leave `/onboarding`) and reconciles once. False when invalid, already
  /// running/done, or the save failed (then [OnboardingState.finishFailed]).
  Future<bool> finish() async {
    final s = state;
    if (!s.isValid || s.finishing) return false;
    emit(s.copyWith(finishing: true, finishFailed: false));
    try {
      for (final r in s.routines) {
        await _routines.save(r);
      }
      await _schedule.save(s.schedule);
      final settings = await _settings.get();
      await _settings.save(settings.copyWith(onboardingCompleted: true));
    } on Object catch (e, st) {
      debugPrint('Onboarding save failed: $e\n$st');
      if (!isClosed) emit(state.copyWith(finishing: false, finishFailed: true));
      return false;
    }
    try {
      await _reconciler.reconcile(ReconcileTrigger.manual);
    } on Object catch (e, st) {
      // Later triggers (resume, watchers) will re-plan; don't trap the user.
      debugPrint('Onboarding reconcile failed: $e\n$st');
    }
    return true;
  }
}
