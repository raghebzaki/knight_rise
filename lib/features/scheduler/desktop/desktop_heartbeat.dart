import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/core/time/location_provider.dart';
import 'package:knight_rise/features/quest_log/domain/usecases/history_usecases.dart';
import 'package:knight_rise/features/scheduler/data/background_tasks.dart';
import 'package:knight_rise/features/scheduler/desktop/desktop_alarm_clock.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/presentation/schedule_sync_service.dart';

/// Desktop replacement for the OS scheduler and the WorkManager safety net.
///
/// Dart timers run on a monotonic clock that stops during system sleep, and
/// App Nap can delay them, so no beat trusts the timer: each one re-derives
/// everything from the wall clock ([Clock.now]). Beats are aligned to wall
/// minutes: every beat arms a one-shot timer for the next minute boundary
/// plus one second, so drift never accumulates.
@desktopEnv
@lazySingleton
class DesktopHeartbeat {
  DesktopHeartbeat(this._clock, this._alarm, this._sync, this._maintainHistory, this._location);

  /// Nominal beat period.
  static const Duration period = Duration(seconds: 60);

  /// A gap between beats longer than this means the machine slept (or the
  /// process stalled) and is treated like an app resume.
  static const Duration wakeGap = Duration(minutes: 2);

  final Clock _clock;
  final DesktopAlarmClock _alarm;
  final ScheduleSyncService _sync;
  final MaintainHistory _maintainHistory;
  final LocationProvider _location;

  Timer? _timer;
  bool _started = false;
  bool _disposed = false;
  bool _beating = false;
  DateTime? _lastBeat;
  late DateTime _lastPeriodic;

  /// Time from [now] to the next minute boundary plus one second (the next
  /// one only once this one has passed); in (0, 60 s].
  @visibleForTesting
  static Duration delayUntilNextBeat(DateTime now) {
    final intoMinute = Duration(seconds: now.second, milliseconds: now.millisecond, microseconds: now.microsecond);
    const offset = Duration(seconds: 1);
    // Before :01 the beat is this minute's boundary + 1 s, otherwise the next one's.
    return intoMinute < offset ? offset - intoMinute : period + offset - intoMinute;
  }

  /// Starts beating. Idempotent.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _lastPeriodic = _clock.now();
    _arm();
  }

  @disposeMethod
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _arm() {
    if (_disposed) return;
    _timer = Timer(delayUntilNextBeat(_clock.now()), () => unawaited(_onTimer()));
  }

  Future<void> _onTimer() async {
    try {
      await beat();
    } finally {
      _arm();
    }
  }

  /// Runs one beat. Skipped while a previous beat is still running. Never throws.
  ///
  /// Order matters: the alarm ticks FIRST so overdue reminders are consumed by
  /// the catch-up rule before a reconcile's diff cancels them as stale.
  @visibleForTesting
  Future<void> beat() async {
    if (_beating) return;
    _beating = true;
    try {
      final now = _clock.now();
      await _step('alarm tick', _alarm.tick);

      final last = _lastBeat;
      final woke = last != null && (now.difference(last) > wakeGap || now.isBefore(last));
      final location = _location.current;
      final dayChanged = last != null && localDateOf(now, location) != localDateOf(last, location);

      if (woke || dayChanged) {
        await _step('resume', _sync.onResume);
        await _step('maintain history', _maintainHistory.call);
        _lastPeriodic = now;
      } else if (now.difference(_lastPeriodic) >= reconcileInterval) {
        await _step('periodic reconcile', () => _sync.reconcileNow(ReconcileTrigger.periodic));
        await _step('maintain history', _maintainHistory.call);
        _lastPeriodic = now;
      }
      _lastBeat = now;
    } finally {
      _beating = false;
    }
  }

  static Future<void> _step(String name, Future<void> Function() step) async {
    try {
      await step();
    } on Object catch (e, st) {
      debugPrint('[heartbeat] $name failed: $e\n$st');
    }
  }
}
