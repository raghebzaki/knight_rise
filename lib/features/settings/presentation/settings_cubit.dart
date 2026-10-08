import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/utils/combine_latest.dart';
import 'package:knight_rise/features/settings/domain/entities/app_settings.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/work_schedule_repository.dart';

class SettingsState extends Equatable {
  const SettingsState({this.loaded = false, this.settings = const AppSettings(), this.schedule = const WorkSchedule()});

  final bool loaded;
  final AppSettings settings;
  final WorkSchedule schedule;

  @override
  List<Object?> get props => [loaded, settings, schedule];
}

/// Settings hub state: app settings plus the saved work schedule (for the
/// summary row). Toggles are written straight to the repository; the sync
/// service reconciles on its own.
@injectable
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._settings, this._workSchedule) : super(const SettingsState()) {
    _sub = combineLatest<SettingsState>(
      [_settings.watch(), _workSchedule.watch()],
      (v) => SettingsState(loaded: true, settings: v[0]! as AppSettings, schedule: v[1]! as WorkSchedule),
    ).listen(emit);
  }

  final SettingsRepository _settings;
  final WorkScheduleRepository _workSchedule;
  late final StreamSubscription<SettingsState> _sub;

  Future<void> setShieldRecoverOnExit({required bool value}) async {
    final current = await _settings.get();
    await _settings.save(current.copyWith(shieldRecoverOnExit: value));
  }

  Future<void> setHapticsEnabled({required bool value}) async {
    final current = await _settings.get();
    await _settings.save(current.copyWith(hapticsEnabled: value));
  }

  /// Allowed streak goal range and step (percent).
  static const streakGoalMin = 50;
  static const streakGoalMax = 100;
  static const streakGoalStep = 5;

  /// Saves the streak goal, clamped to [streakGoalMin]..[streakGoalMax] and
  /// snapped to [streakGoalStep]. Applies to days finalized from now on;
  /// stored days keep the goal they were finalized with.
  Future<void> setStreakThreshold(int percent) async {
    final snapped = ((percent / streakGoalStep).round() * streakGoalStep).clamp(streakGoalMin, streakGoalMax);
    final current = await _settings.get();
    await _settings.save(current.copyWith(streakThresholdPercent: snapped));
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    await super.close();
  }
}
