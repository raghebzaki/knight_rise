import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/time/device_timezone.dart';
import 'package:knight_rise/core/time/location_provider.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/pending_reminder.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/repositories/reconcile_run_repository.dart';
import 'package:knight_rise/features/scheduler/domain/services/schedule_reconciler.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';
import 'package:timezone/timezone.dart' as tz;

part 'diagnostics_cubit.freezed.dart';

/// How far ahead the "Test notification" action schedules.
const Duration kTestNotificationDelay = Duration(minutes: 1);

@freezed
abstract class DiagnosticsState with _$DiagnosticsState {
  const factory DiagnosticsState({
    @Default(false) bool loaded,
    @Default(false) bool busy,
    String? settingsTimezoneId,
    String? deviceTimezoneId,
    @Default(false) bool notificationsEnabled,
    @Default(false) bool canScheduleExact,
    @Default(false) bool precisionTiming,

    /// Sorted by fire time; entries without a payload last.
    @Default(<PendingReminder>[]) List<PendingReminder> pending,

    /// Newest first.
    @Default(<ReconcileRun>[]) List<ReconcileRun> runs,

    /// Last error from a refresh or action.
    String? error,
  }) = _DiagnosticsState;
}

/// State for the dev-only diagnostics screen: current OS / settings status,
/// the pending notification list and the live reconcile audit log.
@injectable
class DiagnosticsCubit extends Cubit<DiagnosticsState> {
  DiagnosticsCubit(
    this._gateway,
    this._settings,
    this._runs,
    this._reconciler,
    this._deviceTimezone,
    this._clock,
    this._location,
  ) : super(const DiagnosticsState());

  final NotificationGateway _gateway;
  final SettingsRepository _settings;
  final ReconcileRunRepository _runs;
  final ScheduleReconciler _reconciler;
  final DeviceTimezone _deviceTimezone;
  final Clock _clock;
  final LocationProvider _location;

  StreamSubscription<List<ReconcileRun>>? _runsSub;

  /// Subscribes to reconcile runs (limit 50) and loads the status.
  Future<void> start() {
    unawaited(_runsSub?.cancel());
    _runsSub = _runs.watchRecent().listen((runs) {
      if (!isClosed) emit(state.copyWith(runs: runs));
    });
    return refresh();
  }

  /// Fire-and-forget [start] for widget creation callbacks.
  void unawaitedStart() => unawaited(start());

  /// Re-reads settings, OS permission state and the pending list.
  Future<void> refresh() async {
    try {
      final settings = await _settings.get();
      final deviceTz = await _deviceTimezone.currentId();
      final enabled = await _gateway.notificationsEnabled();
      final exact = await _gateway.canScheduleExact();
      final pending = await _gateway.pendingReminders();
      if (isClosed) return;
      emit(
        state.copyWith(
          loaded: true,
          settingsTimezoneId: settings.timezoneId,
          deviceTimezoneId: deviceTz,
          notificationsEnabled: enabled,
          canScheduleExact: exact,
          precisionTiming: settings.precisionTiming,
          pending: _sorted(pending),
          error: null,
        ),
      );
    } on Object catch (e) {
      if (!isClosed) emit(state.copyWith(loaded: true, error: e.toString()));
    }
  }

  /// Runs a full diff reconcile with the `manual` trigger.
  Future<void> reconcileNow() => _action(() => _reconciler.reconcile(ReconcileTrigger.manual));

  /// Schedules a hydration test notification [kTestNotificationDelay] from now.
  Future<void> scheduleTest() => _action(() => _gateway.scheduleTest(at: _clock.now().add(kTestNotificationDelay)));

  Future<void> _action(Future<Object?> Function() run) async {
    emit(state.copyWith(busy: true));
    String? failure;
    try {
      await run();
    } on Object catch (e) {
      failure = e.toString();
    }
    if (isClosed) return;
    await refresh();
    // refresh() clears the error, so re-apply the action's own failure.
    if (!isClosed) emit(state.copyWith(busy: false, error: failure ?? state.error));
  }

  /// [t] expressed in the user's current zone, for display.
  DateTime toLocal(DateTime t) => tz.TZDateTime.from(t, _location.current);

  static List<PendingReminder> _sorted(List<PendingReminder> pending) {
    final list = [...pending]
      ..sort((a, b) {
        final x = a.payload?.fireAt;
        final y = b.payload?.fireAt;
        if (x == null && y == null) return a.id.compareTo(b.id);
        if (x == null) return 1;
        if (y == null) return -1;
        final c = x.compareTo(y);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return list;
  }

  @override
  Future<void> close() async {
    await _runsSub?.cancel();
    await super.close();
  }
}
