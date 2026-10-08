import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/core/time/location_provider.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';
import 'package:knight_rise/features/shield/domain/repositories/shield_repository.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/day_override_repository.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/work_schedule_repository.dart';

/// One-tap Shield lengths (architecture doc 4.3).
enum ShieldPreset {
  /// 25 minutes; stored with [ShieldReason.focus].
  min25,

  /// 50 minutes; stored with [ShieldReason.meeting].
  min50,

  /// Until the end of the current work window; [ShieldReason.untilOff].
  untilOff,

  /// A caller-supplied duration; [ShieldReason.custom].
  custom,
}

/// Starts a Shield now, replacing an active one (which is ended at `now`).
///
/// Returns the stored session, or null when `untilOff` is requested outside a
/// work window (there is no Shield outside work hours); in that case an
/// active Shield is left untouched. Other presets run `now + duration` with
/// no cap. Throws [ArgumentError] for [ShieldPreset.custom] without a
/// positive `custom` duration.
@injectable
class StartShield {
  const StartShield(this._shields, this._workSchedule, this._overrides, this._planner, this._clock, this._location);

  final ShieldRepository _shields;
  final WorkScheduleRepository _workSchedule;
  final DayOverrideRepository _overrides;
  final ReminderPlanner _planner;
  final Clock _clock;
  final LocationProvider _location;

  Future<ShieldSession?> call(ShieldPreset preset, {Duration? custom}) async {
    final now = _clock.now();
    final (:end, :reason) = switch (preset) {
      ShieldPreset.min25 => (end: now.add(const Duration(minutes: 25)), reason: ShieldReason.focus),
      ShieldPreset.min50 => (end: now.add(const Duration(minutes: 50)), reason: ShieldReason.meeting),
      ShieldPreset.custom => (end: now.add(_requireDuration(custom)), reason: ShieldReason.custom),
      ShieldPreset.untilOff => (end: await _workWindowEnd(now), reason: ShieldReason.untilOff),
    };
    if (end == null) return null;

    final active = await _shields.active(now);
    if (active != null) await _shields.update(active.copyWith(endedAt: now));

    final session = ShieldSession(startAt: now, endAt: end, reason: reason);
    return session.copyWith(id: await _shields.add(session));
  }

  static Duration _requireDuration(Duration? d) {
    if (d == null || d <= Duration.zero) {
      throw ArgumentError.value(d, 'custom', 'ShieldPreset.custom needs a positive duration');
    }
    return d;
  }

  /// End of the work window containing [now] (today's override applied).
  Future<DateTime?> _workWindowEnd(DateTime now) async {
    final location = _location.current;
    final input = PlannerInput(
      routines: const [],
      schedule: await _workSchedule.get(),
      location: location,
      now: now,
      overrides: await _overrides.getFrom(localDateOf(now, location)),
    );
    return _planner.currentWindow(input)?.end;
  }
}

/// Pushes the active Shield's end out by [Duration]. Null when none is active.
@injectable
class ExtendShield {
  const ExtendShield(this._shields, this._clock);

  final ShieldRepository _shields;
  final Clock _clock;

  Future<ShieldSession?> call(Duration extra) async {
    final active = await _shields.active(_clock.now());
    if (active == null) return null;
    final updated = active.copyWith(endAt: active.endAt.add(extra));
    await _shields.update(updated);
    return updated;
  }
}

/// Ends the active Shield now. Returns the ended session, or null if none.
@injectable
class EndShield {
  const EndShield(this._shields, this._clock);

  final ShieldRepository _shields;
  final Clock _clock;

  Future<ShieldSession?> call() async {
    final now = _clock.now();
    final active = await _shields.active(now);
    if (active == null) return null;
    final ended = active.copyWith(endedAt: now);
    await _shields.update(ended);
    return ended;
  }
}
