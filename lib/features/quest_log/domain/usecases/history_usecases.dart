import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/core/time/location_provider.dart';
import 'package:knight_rise/features/quest_log/domain/repositories/daily_summary_repository.dart';
import 'package:knight_rise/features/quest_log/domain/services/day_summarizer.dart';
import 'package:knight_rise/features/routines/domain/repositories/routine_repository.dart';
import 'package:knight_rise/features/scheduler/domain/repositories/reminder_event_repository.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';
import 'package:knight_rise/features/shield/domain/repositories/shield_repository.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/day_override_repository.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/work_schedule_repository.dart';

/// Raw events, Shield sessions and day overrides are kept this many days;
/// daily summaries are kept forever.
const kRetentionDays = 90;

/// Writes a `DailySummary` for every past local day that has none yet, up to
/// yesterday and at most [kRetentionDays] back (older raw data is pruned).
///
/// History starts at the first recorded activity (completion, snooze or
/// Shield), so a fresh install does not get weeks of empty days. Days are
/// summarized with the current routines, schedule and settings; the hourly
/// background run finalizes each day soon after midnight, before most edits.
///
/// Idempotent and safe across isolates: a day is computed from the same
/// stored data wherever it runs, and the upsert replaces it atomically. Runs
/// in the same isolate are coalesced.
@lazySingleton
class FinalizeDays {
  FinalizeDays(
    this._summaries,
    this._routines,
    this._schedule,
    this._settings,
    this._events,
    this._shields,
    this._overrides,
    this._clock,
    this._location,
    this._summarizer,
  );

  final DailySummaryRepository _summaries;
  final RoutineRepository _routines;
  final WorkScheduleRepository _schedule;
  final SettingsRepository _settings;
  final ReminderEventRepository _events;
  final ShieldRepository _shields;
  final DayOverrideRepository _overrides;
  final Clock _clock;
  final LocationProvider _location;
  final DaySummarizer _summarizer;

  Future<int>? _inFlight;

  /// Returns the number of days written.
  Future<int> call() => _inFlight ??= _run().whenComplete(() => _inFlight = null);

  Future<int> _run() async {
    final now = _clock.now();
    final location = _location.current;
    final today = localDateOf(now, location);
    final windowStart = addDays(today, -kRetentionDays);

    final latest = await _summaries.latestDate();
    var from = latest == null ? windowStart : addDays(latest, 1);
    if (from.isBefore(windowStart)) from = windowStart;
    if (!from.isBefore(today)) return 0;

    final since = startOfDate(from, location);
    final events = await _events.getSince(since);
    final shields = await _shields.getSince(since);
    if (latest == null) {
      final starts = [if (events.isNotEmpty) events.first.at, for (final s in shields) s.startAt];
      if (starts.isEmpty) return 0;
      final firstActivity = localDateOf(starts.reduce((a, b) => a.isBefore(b) ? a : b), location);
      if (firstActivity.isAfter(from)) from = firstActivity;
      if (!from.isBefore(today)) return 0;
    }

    final inputs = SummaryInputs(
      routines: await _routines.getAll(),
      schedule: await _schedule.get(),
      settings: await _settings.get(),
      events: events,
      shields: shields,
      overrides: await _overrides.getFrom(from),
    );
    var written = 0;
    for (var day = from; day.isBefore(today); day = addDays(day, 1)) {
      await _summaries.upsert(_summarizer(inputs, date: day, location: location, at: now));
      written++;
    }
    return written;
  }
}

/// Deletes raw data older than [kRetentionDays] days, at most once per local
/// day. Run it after [FinalizeDays] (see [MaintainHistory]); the cutoff is
/// the start of FinalizeDays' window, so nothing it still needs is removed.
@injectable
class PruneHistory {
  const PruneHistory(this._settings, this._events, this._shields, this._overrides, this._clock, this._location);

  final SettingsRepository _settings;
  final ReminderEventRepository _events;
  final ShieldRepository _shields;
  final DayOverrideRepository _overrides;
  final Clock _clock;
  final LocationProvider _location;

  /// Returns false when it already ran today.
  Future<bool> call() async {
    final now = _clock.now();
    final location = _location.current;
    final today = localDateOf(now, location);
    final last = (await _settings.get()).lastRetentionRunAt;
    if (last != null && localDateOf(last, location) == today) return false;

    final cutoffDate = addDays(today, -kRetentionDays);
    final cutoff = startOfDate(cutoffDate, location);
    await _events.deleteBefore(cutoff);
    await _shields.deleteEndedBefore(cutoff);
    await _overrides.deleteBefore(cutoffDate);
    await _settings.markRetentionRun(now);
    return true;
  }
}

/// Launch, resume and background entry point: finalize, then prune. Pruning
/// is skipped when finalizing throws.
@injectable
class MaintainHistory {
  const MaintainHistory(this._finalize, this._prune);

  final FinalizeDays _finalize;
  final PruneHistory _prune;

  Future<void> call() async {
    await _finalize();
    await _prune();
  }
}
