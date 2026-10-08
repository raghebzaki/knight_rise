import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/features/quest_log/domain/entities/daily_summary.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:knight_rise/features/settings/domain/entities/app_settings.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:timezone/timezone.dart' as tz;

/// Persisted state a day is summarized from. Lists may cover more than the
/// day; [DaySummarizer] keeps only what falls on it.
class SummaryInputs {
  const SummaryInputs({
    required this.routines,
    required this.schedule,
    required this.settings,
    this.events = const [],
    this.shields = const [],
    this.overrides = const [],
  });

  /// The same persisted state the dashboard watches.
  factory SummaryInputs.of(CycleInputs inputs) => SummaryInputs(
    routines: inputs.routines,
    schedule: inputs.schedule,
    settings: inputs.settings,
    events: inputs.todayEvents,
    shields: inputs.shields,
    overrides: inputs.overrides,
  );

  final List<Routine> routines;
  final WorkSchedule schedule;
  final AppSettings settings;
  final List<ReminderEvent> events;
  final List<ShieldSession> shields;
  final List<DayOverride> overrides;
}

/// Pure: one local calendar day + inputs → its [DailySummary].
///
/// Used for finalized past days and for today's live summary; `at` is the
/// finalize time (or now), and nothing after it counts as focus time.
@injectable
class DaySummarizer {
  const DaySummarizer();

  DailySummary call(
    SummaryInputs inputs, {
    required DateTime date,
    required tz.Location location,
    required DateTime at,
  }) {
    final day = dateOnly(date);
    final start = startOfDate(day, location);
    final end = startOfDate(addDays(day, 1), location);
    bool onDay(DateTime t) => !t.isBefore(start) && t.isBefore(end);

    final key = dateKey(day);
    final override = inputs.overrides.where((o) => dateKey(o.date) == key).firstOrNull;
    final isWorkDay = override?.kind != DayOverrideKind.off && inputs.schedule.windowsFor(day.weekday).isNotEmpty;

    final done = inputs.events.where((e) => e.outcome == ReminderOutcome.done && onDay(e.at)).toList();
    final waterMl = done.fold<int>(0, (sum, e) => sum + (e.waterMl ?? 0));
    final hydration = inputs.routines.where((r) => r.type == RoutineType.hydration).firstOrNull;
    final waterTargetMl = (hydration?.dailyTarget ?? 8) * inputs.settings.waterPerTapMl;

    final routines = [
      for (final r in inputs.routines)
        RoutineDaySummary(
          type: r.type,
          done: done.where((e) => e.type == r.type).length,
          target: r.dailyTarget,
          enabled: r.enabled,
        ),
    ]..sort((a, b) => a.type.index.compareTo(b.type.index));

    final focusEnd = at.isBefore(end) ? at : end;
    final summary = DailySummary(
      date: day,
      isWorkDay: isWorkDay,
      waterMl: waterMl,
      waterTargetMl: waterTargetMl,
      focusMinutes: focusMinutes(inputs.shields, from: start, to: focusEnd),
      thresholdPercent: inputs.settings.streakThresholdPercent,
      qualified: false,
      finalizedAt: at,
      routines: routines,
    );
    return summary.copyWith(
      qualified:
          summary.countsTowardStreak &&
          routines.where((r) => r.enabled).every((r) => summary.measureOf(r).reaches(summary.thresholdPercent)),
    );
  }

  /// Whole minutes covered by [shields] between [from] and [to]. Overlapping
  /// sessions count once; a session ended early counts until it ended.
  static int focusMinutes(List<ShieldSession> shields, {required DateTime from, required DateTime to}) {
    if (!to.isAfter(from)) return 0;
    final spans = <(DateTime, DateTime)>[
      for (final s in shields)
        if (s.startAt.isBefore(to) && s.effectiveEnd.isAfter(from))
          (s.startAt.isBefore(from) ? from : s.startAt, s.effectiveEnd.isAfter(to) ? to : s.effectiveEnd),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    var total = Duration.zero;
    DateTime? runStart;
    DateTime? runEnd;
    for (final (s, e) in spans) {
      if (runEnd != null && !s.isAfter(runEnd)) {
        if (e.isAfter(runEnd)) runEnd = e;
        continue;
      }
      if (runStart != null) total += runEnd!.difference(runStart);
      runStart = s;
      runEnd = e;
    }
    if (runStart != null) total += runEnd!.difference(runStart);
    return total.inMinutes;
  }
}
