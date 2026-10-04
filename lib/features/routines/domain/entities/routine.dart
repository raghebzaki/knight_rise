import 'package:freezed_annotation/freezed_annotation.dart';

part 'routine.freezed.dart';

enum RoutineType { hydration, stretch, eyeRest }

/// How the next reminder is placed after the user completes one.
enum ScheduleMode {
  /// Next reminder = completion time + interval (default).
  rolling,

  /// Reminders stay on a fixed grid from the start of the work window.
  fixedGrid,
}

@freezed
abstract class Routine with _$Routine {
  @Assert('intervalMinutes >= 5', 'interval must be at least 5 minutes')
  @Assert('dailyTarget >= 1', 'daily target must be at least 1')
  const factory Routine({
    required RoutineType type,
    required int intervalMinutes,
    required int dailyTarget,
    @Default(true) bool enabled,
    @Default(ScheduleMode.rolling) ScheduleMode mode,
  }) = _Routine;

  const Routine._();

  Duration get interval => Duration(minutes: intervalMinutes);

  /// Defaults from the architecture doc (section 4.1).
  static const defaults = <Routine>[
    Routine(type: RoutineType.hydration, intervalMinutes: 45, dailyTarget: 8),
    Routine(type: RoutineType.stretch, intervalMinutes: 60, dailyTarget: 6),
    Routine(type: RoutineType.eyeRest, intervalMinutes: 20, dailyTarget: 12),
  ];

  /// Allowed interval range per routine, in minutes.
  static ({int min, int max}) intervalRange(RoutineType type) => switch (type) {
    RoutineType.hydration => (min: 15, max: 120),
    RoutineType.stretch => (min: 30, max: 180),
    RoutineType.eyeRest => (min: 15, max: 60),
  };
}
