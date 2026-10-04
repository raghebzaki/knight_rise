import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_window.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:timezone/timezone.dart' as tz;

part 'planner_models.freezed.dart';

/// What the planner needs to know about a routine's recent activity today.
@freezed
abstract class RoutineHistory with _$RoutineHistory {
  const factory RoutineHistory({DateTime? lastDoneAt, DateTime? snoozedUntil, @Default(0) int snoozesSinceDone}) =
      _RoutineHistory;
}

/// Everything the planner reads. Pure data: no I/O.
class PlannerInput {
  const PlannerInput({
    required this.routines,
    required this.schedule,
    required this.location,
    required this.now,
    this.history = const {},
    this.shields = const [],
  });

  final List<Routine> routines;
  final WorkSchedule schedule;
  final tz.Location location;
  final DateTime now;
  final Map<RoutineType, RoutineHistory> history;
  final List<ShieldWindow> shields;

  RoutineHistory historyOf(RoutineType t) => history[t] ?? const RoutineHistory();
}

/// One notification to fire. Routines due within the merge window share one.
@immutable
class PlannedReminder {
  const PlannedReminder({required this.fireAt, required this.types});

  final DateTime fireAt;
  final Set<RoutineType> types;

  /// Deterministic, positive 31-bit id: same slot + routines → same id, so
  /// re-planning is idempotent (cancel what's gone, add what's new).
  int get notificationId {
    final minute = fireAt.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute;
    final mask = types.fold<int>(0, (m, t) => m | (1 << t.index));
    return (minute * 8 + mask) & 0x7fffffff;
  }

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.fireAt.isAtSameMomentAs(fireAt) &&
      other.types.length == types.length &&
      other.types.containsAll(types);

  @override
  int get hashCode => Object.hash(fireAt.millisecondsSinceEpoch, Object.hashAllUnordered(types));

  @override
  String toString() => 'PlannedReminder($fireAt, ${types.map((t) => t.name).join('+')})';
}

/// A routine's status right now.
@immutable
sealed class RoutineStatus {
  const RoutineStatus();
}

/// Turned off by the user.
@immutable
class StatusDisabled extends RoutineStatus {
  const StatusDisabled();

  @override
  bool operator ==(Object other) => other is StatusDisabled;

  @override
  int get hashCode => 0;
}

/// Outside working hours. [nextWorkStart] is null if no work day is configured.
@immutable
class StatusOffDuty extends RoutineStatus {
  const StatusOffDuty(this.nextWorkStart);
  final DateTime? nextWorkStart;

  @override
  bool operator ==(Object other) => other is StatusOffDuty && other.nextWorkStart == nextWorkStart;

  @override
  int get hashCode => Object.hash(StatusOffDuty, nextWorkStart);
}

/// Inside working hours, next reminder at [at] (may be null if none fits
/// within the planning horizon).
@immutable
class StatusUpcoming extends RoutineStatus {
  const StatusUpcoming(this.at);
  final DateTime? at;

  @override
  bool operator ==(Object other) => other is StatusUpcoming && other.at == at;

  @override
  int get hashCode => Object.hash(StatusUpcoming, at);
}

/// A reminder slot has passed without completion.
@immutable
class StatusDue extends RoutineStatus {
  const StatusDue(this.since);
  final DateTime since;

  @override
  bool operator ==(Object other) => other is StatusDue && other.since == since;

  @override
  int get hashCode => Object.hash(StatusDue, since);
}

@immutable
class StatusSnoozed extends RoutineStatus {
  const StatusSnoozed(this.until);
  final DateTime until;

  @override
  bool operator ==(Object other) => other is StatusSnoozed && other.until == until;

  @override
  int get hashCode => Object.hash(StatusSnoozed, until);
}
