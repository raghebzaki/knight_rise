import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:timezone/timezone.dart' as tz;

/// Pure scheduling brain. Given routines, working hours, Shield windows,
/// recent history and `now`, computes when reminders should fire.
///
/// All wall-clock math happens in the user's [tz.Location], so DST
/// transitions and midnight are handled by construction: work windows are
/// built from local calendar dates, while intervals are real elapsed time.
class ReminderPlanner {
  const ReminderPlanner({
    this.horizon = const Duration(hours: 24),
    this.maxCount = 50,
    this.mergeWindow = const Duration(minutes: 5),
  });

  /// How far ahead to plan. The rolling window from the architecture doc.
  final Duration horizon;

  /// Cap on planned notifications (iOS allows 64 pending; keep headroom).
  final int maxCount;

  /// Reminders for different routines this close together share one
  /// notification, fired at the earlier time.
  final Duration mergeWindow;

  /// The next reminders, sorted by time, merged, capped at [maxCount].
  List<PlannedReminder> plan(PlannerInput input) {
    final end = input.now.add(horizon);
    final entries = <({DateTime at, RoutineType type})>[];

    for (final routine in input.routines.where((r) => r.enabled)) {
      final history = input.historyOf(routine.type);
      for (final window in _windowsBetween(input, input.now, end)) {
        for (final t in slotsIn(routine, history, window)) {
          if (t.isAfter(input.now) && !t.isAfter(end) && !_shielded(input, t)) {
            entries.add((at: t, type: routine.type));
          }
        }
      }
    }

    entries.sort((a, b) {
      final c = a.at.compareTo(b.at);
      return c != 0 ? c : a.type.index.compareTo(b.type.index);
    });

    final result = <PlannedReminder>[];
    var i = 0;
    while (i < entries.length && result.length < maxCount) {
      final first = entries[i];
      final types = <RoutineType>{first.type};
      var j = i + 1;
      while (j < entries.length && entries[j].at.difference(first.at) <= mergeWindow) {
        types.add(entries[j].type);
        j++;
      }
      result.add(PlannedReminder(fireAt: tz.TZDateTime.from(first.at, input.location), types: types));
      i = j;
    }
    return result;
  }

  /// Status of one routine at `input.now`.
  RoutineStatus statusOf(RoutineType type, PlannerInput input, {List<PlannedReminder>? plan}) {
    final routine = input.routines.where((r) => r.type == type).firstOrNull;
    if (routine == null || !routine.enabled) return const StatusDisabled();

    final history = input.historyOf(type);
    final snoozed = _effectiveSnooze(history);
    if (snoozed != null && snoozed.isAfter(input.now)) return StatusSnoozed(snoozed);

    final window = currentWindow(input);
    if (window == null) return StatusOffDuty(nextWorkStart(input));

    final overdue = slotsIn(
      routine,
      history,
      window,
    ).where((t) => !t.isAfter(input.now) && !_shielded(input, t)).toList();
    if (overdue.isNotEmpty) return StatusDue(overdue.first);

    final upcoming = (plan ?? this.plan(input)).where((p) => p.types.contains(type)).firstOrNull;
    return StatusUpcoming(upcoming?.fireAt);
  }

  /// The work window containing `now`, if any.
  LocalWindow? currentWindow(PlannerInput input) {
    for (final w in _windowsBetween(input, input.now, input.now)) {
      if (w.contains(input.now)) return w;
    }
    return null;
  }

  /// Start of the next work window after `now` (looks up to 8 days ahead).
  DateTime? nextWorkStart(PlannerInput input) {
    final until = input.now.add(const Duration(days: 8));
    for (final w in _windowsBetween(input, input.now, until)) {
      if (w.start.isAfter(input.now)) return w.start;
    }
    return null;
  }

  /// Earliest moment the status of anything could change: a reminder slot,
  /// a snooze expiring, a window edge, or local midnight. Used to schedule
  /// the next UI refresh.
  DateTime nextChangeAt(PlannerInput input, {List<PlannedReminder>? plan}) {
    final now = input.now;
    final local = tz.TZDateTime.from(now, input.location);
    final candidates = <DateTime>[
      tz.TZDateTime(input.location, local.year, local.month, local.day + 1),
      ?(plan ?? this.plan(input)).firstOrNull?.fireAt,
      for (final h in input.history.values) ?_effectiveSnooze(h),
      for (final w in _windowsBetween(input, now, now)) ...[w.start, w.end],
      ?nextWorkStart(input),
    ];
    return candidates.where((t) => t.isAfter(now)).reduce((a, b) => a.isBefore(b) ? a : b);
  }

  /// Reminder slots for [routine] inside one work [window], before filtering
  /// by `now`, horizon or Shield.
  List<DateTime> slotsIn(Routine routine, RoutineHistory history, LocalWindow window) {
    final interval = routine.interval;
    final lastDone = history.lastDoneAt;
    final snoozed = _effectiveSnooze(history);
    final out = <DateTime>[];

    switch (routine.mode) {
      case ScheduleMode.rolling:
        var anchor = window.start;
        if (lastDone != null && window.contains(lastDone)) anchor = lastDone;
        if (snoozed != null && window.contains(snoozed)) anchor = snoozed.subtract(interval);
        for (var t = anchor.add(interval); t.isBefore(window.end); t = t.add(interval)) {
          out.add(t);
        }
      case ScheduleMode.fixedGrid:
        final floor = _latest(lastDone, snoozed);
        for (var t = window.start.add(interval); t.isBefore(window.end); t = t.add(interval)) {
          if (floor == null || t.isAfter(floor)) out.add(t);
        }
        if (snoozed != null && window.contains(snoozed)) {
          out
            ..add(snoozed)
            ..sort();
        }
    }
    return out;
  }

  /// A snooze only counts if it happened after the last completion.
  DateTime? _effectiveSnooze(RoutineHistory h) {
    final s = h.snoozedUntil;
    if (s == null) return null;
    final done = h.lastDoneAt;
    if (done != null && !s.isAfter(done)) return null;
    return s;
  }

  bool _shielded(PlannerInput input, DateTime t) => input.shields.any((s) => s.covers(t));

  /// Work windows on every local calendar day touched by [from]..[to].
  Iterable<LocalWindow> _windowsBetween(PlannerInput input, DateTime from, DateTime to) sync* {
    final loc = input.location;
    final a = tz.TZDateTime.from(from, loc);
    final b = tz.TZDateTime.from(to, loc);
    var day = DateTime.utc(a.year, a.month, a.day);
    final last = DateTime.utc(b.year, b.month, b.day);
    while (!day.isAfter(last)) {
      for (final w in input.schedule.windowsFor(day.weekday)) {
        yield LocalWindow(_at(loc, day, w.startMinute), _at(loc, day, w.endMinute));
      }
      day = DateTime.utc(day.year, day.month, day.day + 1);
    }
  }

  static tz.TZDateTime _at(tz.Location loc, DateTime day, int minuteOfDay) =>
      tz.TZDateTime(loc, day.year, day.month, day.day, minuteOfDay ~/ 60, minuteOfDay % 60);

  static DateTime? _latest(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}

/// A work-hours `TimeWindow` placed on a concrete local date. `end` is exclusive.
class LocalWindow {
  const LocalWindow(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  @override
  String toString() => 'LocalWindow($start → $end)';
}
