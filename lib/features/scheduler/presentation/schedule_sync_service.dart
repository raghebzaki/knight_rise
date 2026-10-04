import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/time/device_timezone.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/features/routines/domain/repositories/routine_repository.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/repositories/reminder_event_repository.dart';
import 'package:knight_rise/features/scheduler/domain/services/schedule_reconciler.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/work_schedule_repository.dart';
import 'package:timezone/timezone.dart' as tz;

/// UI-isolate hub for reconcile triggers 1, 2 and 6 (launch/resume, config
/// change, timezone change) plus notification-action writes seen via the
/// events stream. Debounces bursts and never runs two reconciles at once.
@lazySingleton
class ScheduleSyncService {
  ScheduleSyncService(
    this._routines,
    this._workSchedule,
    this._settings,
    this._events,
    this._reconciler,
    this._clock,
    this._deviceTimezone,
  );

  static const debounce = Duration(milliseconds: 500);

  final RoutineRepository _routines;
  final WorkScheduleRepository _workSchedule;
  final SettingsRepository _settings;
  final ReminderEventRepository _events;
  final ScheduleReconciler _reconciler;
  final Clock _clock;
  final DeviceTimezone _deviceTimezone;

  final _timezoneChanged = StreamController<void>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  StreamSubscription<Object?>? _eventsSub;
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

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _listen(_routines.watchAll(), ReconcileTrigger.configChange);
    _listen(_workSchedule.watch(), ReconcileTrigger.configChange);
    _listen(_settings.watch().map((s) => s.precisionTiming).distinct(), ReconcileTrigger.configChange);
    _subscribeEvents();
    await _run(ReconcileTrigger.launch);
  }

  Future<void> onResume() async {
    if (!_started || _disposed) return;
    var trigger = ReconcileTrigger.resume;
    try {
      final id = await _deviceTimezone.currentId();
      final settings = await _settings.get();
      if (id != null && id != settings.timezoneId) {
        final previous = settings.timezoneId;
        if (previous != null) _applyLocation(tz.getLocation(id));
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

  @disposeMethod
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_eventsSub?.cancel());
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    unawaited(_timezoneChanged.close());
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
    _eventsDay = _today();
    _eventsSub = _events
        .watchSince(_eventsDay!)
        .skip(1)
        .listen((_) => _debounced(ReconcileTrigger.action), onError: _logError);
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
          await _reconciler.reconcile(next);
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

  static void _logError(Object e, [StackTrace? st]) => debugPrint('ScheduleSyncService: $e\n${st ?? ''}');
}
