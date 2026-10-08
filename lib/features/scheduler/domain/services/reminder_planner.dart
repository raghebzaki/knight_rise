import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_window.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';
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
  ///
  /// Slots inside a Shield are dropped. With `recoverOnExit`, a recovery
  /// reminder ("Shield down") is added when each Shield ends, listing the
  /// routines it held back.
  ///
  /// Merge clusters are formed over the whole local day (from the local
  /// midnight of `now`), independent of `now`, and only then are clusters whose
  /// fire time has passed dropped. So a slot absorbed into an earlier,
  /// already-delivered notification is never re-planned on its own.
  List<PlannedReminder> plan(PlannerInput input) {
    final end = input.now.add(horizon);
    final localNow = tz.TZDateTime.from(input.now, input.location);
    final dayStart = tz.TZDateTime(input.location, localNow.year, localNow.month, localNow.day);
    final entries = <_Entry>[];

    for (final routine in input.routines.where((r) => r.enabled)) {
      final history = input.historyOf(routine.type);
      for (final window in _windowsBetween(input, dayStart, end)) {
        for (final t in slotsIn(routine, history, window)) {
          if (!t.isAfter(end) && !_shielded(input, t)) {
            entries.add(_Entry(t, {routine.type}));
          }
        }
      }
    }
    if (input.recoverOnExit) entries.addAll(_recoveryEntries(input, end));

    entries.sort((a, b) {
      final c = a.at.compareTo(b.at);
      return c != 0 ? c : a.firstTypeIndex.compareTo(b.firstTypeIndex);
    });

    final result = <PlannedReminder>[];
    var i = 0;
    while (i < entries.length && result.length < maxCount) {
      final first = entries[i];
      final members = <_Entry>[first];
      var j = i + 1;
      while (j < entries.length && entries[j].at.difference(first.at) <= mergeWindow) {
        members.add(entries[j]);
        j++;
      }
      i = j;
      var kept = members;
      if (!first.at.isAfter(input.now)) {
        // The cluster's first entry already passed: it was delivered together
        // with its absorbed members. Only a recovery entry still in the future
        // was never part of that delivery (the Shield ended after it fired),
        // so it keeps its own notification.
        kept = members.where((e) => e.recovery && e.at.isAfter(input.now)).toList();
        if (kept.isEmpty) continue;
      }
      final types = <RoutineType>{for (final e in kept) ...e.types};
      result.add(
        PlannedReminder(
          fireAt: tz.TZDateTime.from(kept.first.at, input.location),
          types: types,
          recovery: kept.any((e) => e.recovery),
        ),
      );
    }
    return result;
  }

  /// Shield windows with overlapping or touching spans unioned, oldest first.
  /// The merged window keeps `endedAt` only when its final end was manual.
  List<ShieldWindow> mergedShields(List<ShieldWindow> shields) {
    final sorted = shields.where((s) => s.end.isAfter(s.start)).toList()..sort((a, b) => a.start.compareTo(b.start));
    final out = <ShieldWindow>[];
    for (final s in sorted) {
      if (out.isEmpty || s.start.isAfter(out.last.end)) {
        out.add(s);
        continue;
      }
      final cur = out.last;
      if (s.end.isAfter(cur.end)) {
        out[out.length - 1] = ShieldWindow(start: cur.start, end: s.end, endedAt: s.endedAt);
      } else if (s.end.isAtSameMomentAs(cur.end) && (s.endedAt == null || cur.endedAt == null)) {
        out[out.length - 1] = ShieldWindow(start: cur.start, end: cur.end);
      }
    }
    return out;
  }

  /// "Return Quest" entries: one per merged Shield that has not fully played
  /// out yet, listing the routines it suppressed.
  Iterable<_Entry> _recoveryEntries(PlannerInput input, DateTime horizonEnd) sync* {
    for (final w in mergedShields(input.shields)) {
      // A manual early end still gets its ping, just after the end.
      final at = w.endedAt != null ? w.endedAt!.add(const Duration(minutes: 1)) : w.end;
      if (!at.isAfter(input.now) || at.isAfter(horizonEnd)) continue;
      if (!_inWorkWindow(input, at)) continue;
      final types = _suppressedBy(input, w);
      if (types.isNotEmpty) yield _Entry(at, types, recovery: true);
    }
  }

  /// Enabled routines with at least one candidate slot inside [shield],
  /// regardless of `now` and honoring history (slots superseded by a later
  /// completion are not generated by [slotsIn]).
  Set<RoutineType> _suppressedBy(PlannerInput input, ShieldWindow shield) {
    final windows = _windowsBetween(input, shield.start, shield.end).toList();
    final types = <RoutineType>{};
    for (final routine in input.routines.where((r) => r.enabled)) {
      final history = input.historyOf(routine.type);
      final hit = windows.any((w) => slotsIn(routine, history, w).any(shield.covers));
      if (hit) types.add(routine.type);
    }
    return types;
  }

  bool _inWorkWindow(PlannerInput input, DateTime t) => _windowsBetween(input, t, t).any((w) => w.contains(t));

  /// Status of one routine at `input.now`.
  RoutineStatus statusOf(RoutineType type, PlannerInput input, {List<PlannedReminder>? plan}) {
    final routine = input.routines.where((r) => r.type == type).firstOrNull;
    if (routine == null || !routine.enabled) return const StatusDisabled();

    final history = input.historyOf(type);
    final window = currentWindow(input);

    // An active Shield beats everything except Disabled and OffDuty.
    final shield = activeShield(input);
    if (shield != null && window != null) return StatusShielded(shield.end);

    final snoozed = _effectiveSnooze(history);
    if (snoozed != null && snoozed.isAfter(input.now)) return StatusSnoozed(snoozed);

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

  /// The (merged) Shield window covering `now`, if any.
  ShieldWindow? activeShield(PlannerInput input) =>
      mergedShields(input.shields).where((s) => s.covers(input.now)).firstOrNull;

  /// The work window containing `now`, if any. Honors the day's override.
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
      for (final s in input.shields) ...[
        s.start,
        s.end,
        if (s.endedAt != null) s.endedAt!.add(const Duration(minutes: 1)),
      ],
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
      final ov = input.overrideFor(day);
      if (ov?.kind != DayOverrideKind.off) {
        final windows = input.schedule.windowsFor(day.weekday);
        for (var i = 0; i < windows.length; i++) {
          final w = windows[i];
          var endMinute = w.endMinute;
          // "Working late" stretches the last window, never past midnight.
          if (ov != null && i == windows.length - 1) {
            endMinute = (endMinute + (ov.extendMinutes ?? 0)).clamp(w.endMinute, 1440);
          }
          yield LocalWindow(_at(loc, day, w.startMinute), _at(loc, day, endMinute));
        }
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

class _Entry {
  _Entry(this.at, this.types, {this.recovery = false});

  final DateTime at;
  final Set<RoutineType> types;
  final bool recovery;

  int get firstTypeIndex => types.map((t) => t.index).reduce((a, b) => a < b ? a : b);
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
