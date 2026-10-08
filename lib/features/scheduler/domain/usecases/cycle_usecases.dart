import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/core/utils/combine_latest.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/routines/domain/repositories/routine_repository.dart';
import 'package:knight_rise/features/scheduler/domain/entities/cycle_snapshot.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/scheduler/domain/repositories/reminder_event_repository.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/settings/domain/entities/app_settings.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';
import 'package:knight_rise/features/shield/domain/repositories/shield_repository.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/day_override_repository.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/work_schedule_repository.dart';
import 'package:timezone/timezone.dart' as tz;

/// Max snoozes per routine between completions (architecture doc 4.2).
const kMaxSnoozes = 3;

/// Snooze length offered from notifications and the dashboard.
const kSnoozeDuration = Duration(minutes: 10);

/// Persisted state the cycle engine is computed from.
class CycleInputs {
  const CycleInputs({
    required this.routines,
    required this.schedule,
    required this.todayEvents,
    required this.settings,
    this.shields = const [],
    this.overrides = const [],
  });

  final List<Routine> routines;
  final WorkSchedule schedule;
  final List<ReminderEvent> todayEvents;
  final AppSettings settings;

  /// Shield sessions that have not ended before the start of the local day.
  final List<ShieldSession> shields;

  /// Day overrides dated today or later.
  final List<DayOverride> overrides;
}

/// Derives per-routine history (last completion, active snooze) from events.
Map<RoutineType, RoutineHistory> historyFromEvents(Iterable<ReminderEvent> events) {
  final sorted = [...events]..sort((a, b) => a.at.compareTo(b.at));
  final result = <RoutineType, RoutineHistory>{};
  for (final e in sorted) {
    final h = result[e.type] ?? const RoutineHistory();
    result[e.type] = switch (e.outcome) {
      ReminderOutcome.done => RoutineHistory(lastDoneAt: e.at),
      ReminderOutcome.snoozed => h.copyWith(snoozedUntil: e.snoozedUntil, snoozesSinceDone: h.snoozesSinceDone + 1),
      _ => h,
    };
  }
  return result;
}

/// Streams [CycleInputs] for the local day starting at `dayStart`.
@injectable
class WatchCycleInputs {
  const WatchCycleInputs(this._routines, this._schedule, this._events, this._settings, this._shields, this._overrides);

  final RoutineRepository _routines;
  final WorkScheduleRepository _schedule;
  final ReminderEventRepository _events;
  final SettingsRepository _settings;
  final ShieldRepository _shields;
  final DayOverrideRepository _overrides;

  /// `dayStart` is local midnight of the day to show; overrides are watched
  /// from that date onwards so tomorrow's "day off" is already known.
  Stream<CycleInputs> call(DateTime dayStart) => combineLatest<CycleInputs>(
    [
      _routines.watchAll(),
      _schedule.watch(),
      _events.watchSince(dayStart),
      _settings.watch(),
      _shields.watchSince(dayStart),
      _overrides.watchFrom(dateOnly(dayStart)),
    ],
    (v) => CycleInputs(
      routines: v[0]! as List<Routine>,
      schedule: v[1]! as WorkSchedule,
      todayEvents: v[2]! as List<ReminderEvent>,
      settings: v[3]! as AppSettings,
      shields: v[4]! as List<ShieldSession>,
      overrides: v[5]! as List<DayOverride>,
    ),
  );
}

/// Pure: inputs + now → everything the dashboard shows.
@injectable
class BuildCycleSnapshot {
  const BuildCycleSnapshot(this._planner);

  final ReminderPlanner _planner;

  CycleSnapshot call(CycleInputs inputs, {required DateTime now, required tz.Location location}) {
    final dayStart = startOfLocalDay(now, location);
    final today = inputs.todayEvents.where((e) => !e.at.isBefore(dayStart)).toList();
    final history = historyFromEvents(today);
    final input = PlannerInput(
      routines: inputs.routines,
      schedule: inputs.schedule,
      location: location,
      now: now,
      history: history,
      shields: [for (final s in inputs.shields) s.toWindow()],
      recoverOnExit: inputs.settings.shieldRecoverOnExit,
      overrides: inputs.overrides,
    );
    final plan = _planner.plan(input);

    final views = [
      for (final r in inputs.routines)
        RoutineView(
          routine: r,
          status: _planner.statusOf(r.type, input, plan: plan),
          doneToday: today.where((e) => e.type == r.type && e.outcome == ReminderOutcome.done).length,
          canSnooze: (history[r.type]?.snoozesSinceDone ?? 0) < kMaxSnoozes,
        ),
    ];

    final hydration = inputs.routines.where((r) => r.type == RoutineType.hydration).firstOrNull;
    return CycleSnapshot(
      computedAt: now,
      routines: views,
      onDuty: _planner.currentWindow(input) != null,
      nextUp: plan.firstOrNull,
      nextWorkStart: _planner.nextWorkStart(input),
      activeShield: inputs.shields.where((s) => s.isActiveAt(now)).lastOrNull,
      todayOverride: input.overrideFor(localDateOf(now, location)),
      nextRecovery: plan.where((p) => p.recovery).firstOrNull,
      waterMlToday: today.fold<int>(0, (sum, e) => sum + (e.waterMl ?? 0)),
      waterTargetMl: (hydration?.dailyTarget ?? 8) * inputs.settings.waterPerTapMl,
      nextChangeAt: _planner.nextChangeAt(input, plan: plan),
    );
  }
}

/// Marks a routine done now. Hydration also logs water: `waterMl` when given,
/// otherwise one tap (`settings.waterPerTapMl`, 250 ml by default).
@injectable
class CompleteRoutine {
  const CompleteRoutine(this._events, this._settings, this._clock);

  final ReminderEventRepository _events;
  final SettingsRepository _settings;
  final Clock _clock;

  Future<void> call(RoutineType type, {DateTime? scheduledAt, int? waterMl}) async {
    final settings = await _settings.get();
    await _events.add(
      ReminderEvent(
        type: type,
        outcome: ReminderOutcome.done,
        at: _clock.now(),
        scheduledAt: scheduledAt,
        waterMl: type == RoutineType.hydration ? (waterMl ?? settings.waterPerTapMl) : null,
      ),
    );
  }
}

/// Snoozes a routine for [kSnoozeDuration]. Returns false once the routine
/// has used [kMaxSnoozes] snoozes since its last completion.
@injectable
class SnoozeRoutine {
  const SnoozeRoutine(this._events, this._clock, this._location);

  final ReminderEventRepository _events;
  final Clock _clock;
  final tz.Location _location;

  Future<bool> call(RoutineType type, {DateTime? scheduledAt}) async {
    final now = _clock.now();
    final today = await _events.getSince(startOfLocalDay(now, _location));
    final used = historyFromEvents(today)[type]?.snoozesSinceDone ?? 0;
    if (used >= kMaxSnoozes) return false;
    await _events.add(
      ReminderEvent(
        type: type,
        outcome: ReminderOutcome.snoozed,
        at: now,
        scheduledAt: scheduledAt,
        snoozedUntil: now.add(kSnoozeDuration),
      ),
    );
    return true;
  }
}
