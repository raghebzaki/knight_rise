import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/time/device_timezone.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/core/time/timezone_loader.dart';
import 'package:knight_rise/features/routines/domain/repositories/routine_repository.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/repositories/reconcile_run_repository.dart';
import 'package:knight_rise/features/scheduler/domain/repositories/reminder_event_repository.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/scheduler/domain/services/schedule_reconciler.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';
import 'package:knight_rise/features/shield/domain/repositories/shield_repository.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/day_override_repository.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/work_schedule_repository.dart';
import 'package:timezone/timezone.dart' as tz;

/// Source of the "reminders were paused" signal (see
/// [ScheduleSyncService.remindersWerePaused]). The home page depends on this
/// interface so tests can fake it.
abstract interface class RemindersPausedSource {
  /// Emits when a launch / resume reconcile found the schedule empty.
  Stream<void> get remindersWerePaused;

  /// When the last such signal fired (null if none this process). Lets a page
  /// that opens after the launch reconcile still show the banner.
  DateTime? get remindersPausedAt;
}

/// UI-isolate hub for reconcile triggers 1, 2 and 6 (launch/resume, config
/// change, timezone change) plus notification-action writes seen via the
/// events stream. Debounces bursts and never runs two reconciles at once.
@lazySingleton
class ScheduleSyncService implements RemindersPausedSource {
  ScheduleSyncService(
    this._routines,
    this._workSchedule,
    this._settings,
    this._events,
    this._shields,
    this._overrides,
    this._reconciler,
    this._clock,
    this._deviceTimezone,
    this._runs,
  );

  static const debounce = Duration(milliseconds: 500);

  /// How far ahead the planner arms reminders; runs older than this leave the
  /// OS schedule empty by design.
  static final Duration _horizon = const ReminderPlanner().horizon;

  final RoutineRepository _routines;
  final WorkScheduleRepository _workSchedule;
  final SettingsRepository _settings;
  final ReminderEventRepository _events;
  final ShieldRepository _shields;
  final DayOverrideRepository _overrides;
  final ScheduleReconciler _reconciler;
  final Clock _clock;
  final DeviceTimezone _deviceTimezone;
  final ReconcileRunRepository _runs;

  final _timezoneChanged = StreamController<void>.broadcast();
  final _paused = StreamController<void>.broadcast();
  DateTime? _pausedAt;
  final _subs = <StreamSubscription<Object?>>[];
  StreamSubscription<Object?>? _eventsSub;
  StreamSubscription<Object?>? _shieldsSub;
  StreamSubscription<Object?>? _overridesSub;
  DateTime? _eventsDay;

  Timer? _timer;
  ReconcileTrigger? _pending;
  bool _running = false;
  ReconcileTrigger? _rerun;
  bool _started = false;
  bool _disposed = false;

  /// Emits after the device timezone changed and `tz.local` / the registered
  /// `tz.Location` were replaced, so the app can rebuild.
  Stream<void> get timezoneChanged => _timezoneChanged.stream;

  /// Emits when a `launch` or `resume` reconcile ends up re-adding the whole
  /// plan although an earlier run exists: the diff found nothing pending, so
  /// the OS schedule was wiped or ran dry (force-stop, OEM task killer, or a
  /// long gap without the app). Heuristic: a run with `error == null`,
  /// `planned > 0` and `added == planned`. The very first run ever does not
  /// count (nothing was armed before), nor does one whose previous run is
  /// older than the planning horizon (the armed reminders ran out normally).
  @override
  Stream<void> get remindersWerePaused => _paused.stream;

  @override
  DateTime? get remindersPausedAt => _pausedAt;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _listen(_routines.watchAll(), ReconcileTrigger.configChange);
    _listen(_workSchedule.watch(), ReconcileTrigger.configChange);
    _listen(
      _settings.watch().map((s) => (s.precisionTiming, s.shieldRecoverOnExit)).distinct(),
      ReconcileTrigger.configChange,
    );
    _subscribeEvents();
    await _persistTimezoneIfUnset();
    if (_disposed) return;
    await _run(ReconcileTrigger.launch);
  }

  /// First launch: remember the device zone so later resumes can detect a
  /// change. Does not emit [timezoneChanged]; the location was already
  /// resolved from the device at startup.
  Future<void> _persistTimezoneIfUnset() async {
    try {
      final settings = await _settings.get();
      if (settings.timezoneId != null) return;
      final id = await _deviceTimezone.currentId();
      if (id != null) await _settings.save(settings.copyWith(timezoneId: id));
    } on Object catch (e, st) {
      debugPrint('Timezone persist failed: $e\n$st');
    }
  }

  Future<void> onResume() async {
    if (!_started || _disposed) return;
    var trigger = ReconcileTrigger.resume;
    try {
      final id = await _deviceTimezone.currentId();
      final settings = await _settings.get();
      if (id != null && id != settings.timezoneId) {
        final previous = settings.timezoneId;
        if (previous != null) _applyLocation(resolveLocation(id, utcOffset: DateTime.now().timeZoneOffset));
        await _settings.save(settings.copyWith(timezoneId: id));
        if (previous != null) {
          trigger = ReconcileTrigger.timezoneChange;
          if (!_disposed) _timezoneChanged.add(null);
        }
      }
    } on Object catch (e, st) {
      debugPrint('Timezone check failed: $e\n$st');
    }
    if (_disposed) return;
    if (_eventsDay != _today()) _subscribeEvents();
    await _run(trigger);
  }

  /// Runs a reconcile for [trigger] now, serialized with the service's own
  /// runs. No-op before [start] or after [dispose]. Used by the desktop
  /// heartbeat as the in-process stand-in for the hourly background task.
  Future<void> reconcileNow(ReconcileTrigger trigger) async {
    if (!_started || _disposed) return;
    await _run(trigger);
  }

  @disposeMethod
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_eventsSub?.cancel());
    unawaited(_shieldsSub?.cancel());
    unawaited(_overridesSub?.cancel());
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    unawaited(_timezoneChanged.close());
    unawaited(_paused.close());
  }

  static void _applyLocation(tz.Location location) {
    tz.setLocalLocation(location);
    final wasAllowed = getIt.allowReassignment;
    getIt.allowReassignment = true;
    try {
      getIt.registerSingleton<tz.Location>(location);
    } finally {
      getIt.allowReassignment = wasAllowed;
    }
  }

  DateTime _today() => startOfLocalDay(_clock.now(), tz.local);

  void _listen(Stream<Object?> stream, ReconcileTrigger trigger) {
    _subs.add(stream.skip(1).listen((_) => _debounced(trigger), onError: _logError));
  }

  void _subscribeEvents() {
    unawaited(_eventsSub?.cancel());
    unawaited(_shieldsSub?.cancel());
    unawaited(_overridesSub?.cancel());
    final day = _eventsDay = _today();
    _eventsSub = _events.watchSince(day).skip(1).listen((_) => _debounced(ReconcileTrigger.action), onError: _logError);
    // Shield and day-override edits change what the plan contains, so they
    // are config changes (full replace), like routine or work-hours edits.
    _shieldsSub = _shields
        .watchSince(day)
        .skip(1)
        .listen((_) => _debounced(ReconcileTrigger.configChange), onError: _logError);
    _overridesSub = _overrides
        .watchFrom(dateOnly(day))
        .skip(1)
        .listen((_) => _debounced(ReconcileTrigger.configChange), onError: _logError);
  }

  void _debounced(ReconcileTrigger trigger) {
    if (_disposed) return;
    _pending = _merge(_pending, trigger);
    _timer?.cancel();
    _timer = Timer(debounce, () {
      final t = _pending!;
      _pending = null;
      unawaited(_run(t));
    });
  }

  /// A burst containing a config change stays a config change.
  static ReconcileTrigger _merge(ReconcileTrigger? current, ReconcileTrigger next) =>
      current == ReconcileTrigger.configChange || next == ReconcileTrigger.configChange
      ? ReconcileTrigger.configChange
      : next;

  /// Runs [trigger] now, or queues exactly one follow-up run if busy.
  Future<void> _run(ReconcileTrigger trigger) async {
    if (_running) {
      _rerun = _merge(_rerun, trigger);
      return;
    }
    _running = true;
    try {
      var next = trigger;
      while (true) {
        try {
          final watchPaused = next == ReconcileTrigger.launch || next == ReconcileTrigger.resume;
          final hadPrevious = watchPaused && await _hasRecentRun();
          final run = await _reconciler.reconcile(next);
          if (hadPrevious && !_disposed && run.error == null && run.planned > 0 && run.added == run.planned) {
            _pausedAt = _clock.now();
            _paused.add(null);
          }
        } on Object catch (e, st) {
          _logError(e, st);
        }
        final again = _rerun;
        if (again == null || _disposed) break;
        _rerun = null;
        next = again;
      }
    } finally {
      _running = false;
    }
  }

  /// True when the previous reconcile ran within the planning horizon before
  /// now. An older run (e.g. Thursday evening -> Sunday morning) legitimately
  /// leaves nothing armed, so a full re-add is expected and not a "pause".
  Future<bool> _hasRecentRun() async {
    try {
      final recent = await _runs.watchRecent(limit: 1).first;
      if (recent.isEmpty) return false;
      return _clock.now().difference(recent.first.at) <= _horizon;
    } on Object catch (e, st) {
      _logError(e, st);
      return false;
    }
  }

  static void _logError(Object e, [StackTrace? st]) => debugPrint('ScheduleSyncService: $e\n${st ?? ''}');
}
