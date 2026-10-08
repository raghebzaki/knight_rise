import 'dart:async';

import 'package:knight_rise/core/time/device_timezone.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/core/time/location_provider.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/pending_reminder.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/routines/domain/repositories/routine_repository.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/scheduler/domain/repositories/reconcile_run_repository.dart';
import 'package:knight_rise/features/scheduler/domain/repositories/reminder_event_repository.dart';
import 'package:knight_rise/features/scheduler/domain/services/schedule_reconciler.dart';
import 'package:knight_rise/features/settings/domain/entities/app_settings.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';
import 'package:knight_rise/features/shield/domain/repositories/shield_repository.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/day_override_repository.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/work_schedule_repository.dart';
import 'package:timezone/timezone.dart' as tz;

/// In-memory repositories that behave like the Drift ones: every watch()
/// emits the current value immediately and again after each write.
class _Cell<T> {
  _Cell(this.value);
  T value;
  final _changes = StreamController<void>.broadcast();

  Stream<R> watch<R>(R Function(T) map) {
    late StreamController<R> controller;
    StreamSubscription<void>? sub;
    controller = StreamController<R>(
      onListen: () {
        controller.add(map(value));
        sub = _changes.stream.listen((_) => controller.add(map(value)));
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  void set(T v) {
    value = v;
    _changes.add(null);
  }
}

class FakeRoutineRepository implements RoutineRepository {
  FakeRoutineRepository([List<Routine> initial = Routine.defaults]) : _cell = _Cell([...initial]);
  final _Cell<List<Routine>> _cell;

  @override
  Stream<List<Routine>> watchAll() => _cell.watch((v) => v);

  @override
  Future<List<Routine>> getAll() async => _cell.value;

  @override
  Future<void> save(Routine routine) async => _cell.set([
    for (final r in _cell.value)
      if (r.type == routine.type) routine else r,
  ]);
}

class FakeWorkScheduleRepository implements WorkScheduleRepository {
  FakeWorkScheduleRepository([WorkSchedule? initial]) : _cell = _Cell(initial ?? WorkSchedule.standard());
  final _Cell<WorkSchedule> _cell;
  WorkSchedule get current => _cell.value;

  @override
  Stream<WorkSchedule> watch() => _cell.watch((v) => v);

  @override
  Future<WorkSchedule> get() async => _cell.value;

  @override
  Future<void> save(WorkSchedule schedule) async => _cell.set(schedule);
}

class FakeReminderEventRepository implements ReminderEventRepository {
  final _cell = _Cell<List<ReminderEvent>>([]);
  List<ReminderEvent> get all => _cell.value;

  List<ReminderEvent> _since(DateTime since) => _cell.value.where((e) => !e.at.isBefore(since)).toList();

  @override
  Stream<List<ReminderEvent>> watchSince(DateTime since) => _cell.watch((_) => _since(since));

  @override
  Future<List<ReminderEvent>> getSince(DateTime since) async => _since(since);

  @override
  Future<int> add(ReminderEvent event) async {
    final id = _cell.value.length + 1;
    _cell.set([..._cell.value, event.copyWith(id: id)]);
    return id;
  }

  @override
  Future<void> delete(int id) async => _cell.set([
    for (final e in _cell.value)
      if (e.id != id) e,
  ]);

  @override
  Future<int> deleteBefore(DateTime cutoff) async {
    final kept = _cell.value.where((e) => !e.at.isBefore(cutoff)).toList();
    final removed = _cell.value.length - kept.length;
    _cell.set(kept);
    return removed;
  }
}

class FakeShieldRepository implements ShieldRepository {
  final _cell = _Cell<List<ShieldSession>>([]);
  List<ShieldSession> get all => _cell.value;

  List<ShieldSession> _since(DateTime since) => _cell.value.where((s) => s.effectiveEnd.isAfter(since)).toList();

  @override
  Stream<List<ShieldSession>> watchSince(DateTime since) => _cell.watch((_) => _since(since));

  @override
  Future<List<ShieldSession>> getSince(DateTime since) async => _since(since);

  @override
  Future<int> add(ShieldSession session) async {
    final id = _cell.value.length + 1;
    _cell.set([..._cell.value, session.copyWith(id: id)]);
    return id;
  }

  @override
  Future<void> update(ShieldSession session) async => _cell.set([
    for (final s in _cell.value)
      if (s.id == session.id) session else s,
  ]);

  @override
  Future<ShieldSession?> active(DateTime now) async =>
      (_cell.value.where((s) => s.isActiveAt(now)).toList()..sort((a, b) => a.startAt.compareTo(b.startAt))).lastOrNull;

  @override
  Future<int> deleteEndedBefore(DateTime cutoff) async {
    final kept = _cell.value.where((s) => !s.endAt.isBefore(cutoff)).toList();
    final removed = _cell.value.length - kept.length;
    _cell.set(kept);
    return removed;
  }
}

class FakeDayOverrideRepository implements DayOverrideRepository {
  final _cell = _Cell<List<DayOverride>>([]);
  List<DayOverride> get all => _cell.value;

  List<DayOverride> _from(DateTime date) {
    final key = dateKey(date);
    return _cell.value.where((o) => dateKey(o.date).compareTo(key) >= 0).toList()
      ..sort((a, b) => dateKey(a.date).compareTo(dateKey(b.date)));
  }

  @override
  Stream<List<DayOverride>> watchFrom(DateTime date) => _cell.watch((_) => _from(date));

  @override
  Future<List<DayOverride>> getFrom(DateTime date) async => _from(date);

  @override
  Future<void> set(DayOverride override) async => _cell.set([
    for (final o in _cell.value)
      if (dateKey(o.date) != dateKey(override.date)) o,
    override,
  ]);

  @override
  Future<void> clear(DateTime date) async => _cell.set([
    for (final o in _cell.value)
      if (dateKey(o.date) != dateKey(date)) o,
  ]);

  @override
  Future<int> deleteBefore(DateTime date) async {
    final key = dateKey(date);
    final kept = _cell.value.where((o) => dateKey(o.date).compareTo(key) >= 0).toList();
    final removed = _cell.value.length - kept.length;
    _cell.set(kept);
    return removed;
  }
}

class FakeSettingsRepository implements SettingsRepository {
  final _cell = _Cell<AppSettings>(const AppSettings());
  AppSettings get current => _cell.value;

  @override
  Stream<AppSettings> watch() => _cell.watch((v) => v);

  @override
  Future<AppSettings> get() async => _cell.value;

  @override
  Future<void> save(AppSettings settings) async => _cell.set(settings);

  @override
  Future<void> markRetentionRun(DateTime at) async => _cell.set(_cell.value.copyWith(lastRetentionRunAt: at));
}

/// Records every reconcile call. [delay] simulates a slow reconcile.
class FakeScheduleReconciler implements ScheduleReconciler {
  FakeScheduleReconciler({this.delay = Duration.zero});
  Duration delay;
  final List<ReconcileTrigger> calls = [];
  int concurrent = 0;
  int maxConcurrent = 0;
  Object? throwOnNext;

  @override
  Future<ReconcileRun> reconcile(ReconcileTrigger trigger) async {
    calls.add(trigger);
    concurrent++;
    if (concurrent > maxConcurrent) maxConcurrent = concurrent;
    try {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      final err = throwOnNext;
      if (err != null) {
        throwOnNext = null;
        // Tests throw arbitrary objects on purpose.
        // ignore: only_throw_errors
        throw err;
      }
      return ReconcileRun(at: DateTime(2026), trigger: trigger, planned: 0, added: 0, cancelled: 0);
    } finally {
      concurrent--;
    }
  }
}

class FakeDeviceTimezone implements DeviceTimezone {
  FakeDeviceTimezone(this.id);
  String? id;

  @override
  Future<String?> currentId() async => id;
}

class FakeReconcileRunRepository implements ReconcileRunRepository {
  final List<ReconcileRun> runs = [];

  @override
  Future<void> record(ReconcileRun run) async => runs.add(run);

  @override
  Stream<List<ReconcileRun>> watchRecent({int limit = 50}) => Stream.value(runs.reversed.take(limit).toList());

  final List<int> pruneKeeps = [];

  @override
  Future<void> prune({int keep = 200}) async => pruneKeeps.add(keep);
}

class FakeLocationProvider implements LocationProvider {
  FakeLocationProvider(this.location);
  tz.Location location;

  @override
  tz.Location get current => location;
}

/// Records every call. [pending] is what [pendingIds] returns; [schedule] and
/// [cancel] do not mutate it, so tests control the "OS state" explicitly.
class FakeNotificationGateway implements NotificationGateway {
  final List<({PlannedReminder reminder, bool exact})> scheduled = [];
  final List<int> cancelled = [];
  int cancelAllCalls = 0;
  int canScheduleExactCalls = 0;
  Set<int> pending = {};
  bool exactAllowed = true;

  /// What [notificationsEnabled] returns.
  bool enabled = true;

  /// When true, [requestPermission] flips [enabled] on (user taps Allow).
  bool grantOnRequest = true;
  int requestPermissionCalls = 0;

  /// What [pendingReminders] returns; defaults to payload-less entries for [pending].
  List<PendingReminder>? pendingReminderList;

  /// Fire times passed to [scheduleTest].
  final List<DateTime> testScheduled = [];

  /// When set, [schedule] throws it.
  Object? throwOnSchedule;

  /// Call order, e.g. `cancelAll`, `schedule:<id>`, `cancel:<id>`.
  final List<String> log = [];

  @override
  Future<void> initialize({required void Function(ReminderAction action) onForegroundAction}) async {}

  @override
  Future<void> schedule(PlannedReminder reminder, {required bool exact}) async {
    final err = throwOnSchedule;
    if (err != null) {
      // Tests throw arbitrary objects on purpose.
      // ignore: only_throw_errors
      throw err;
    }
    scheduled.add((reminder: reminder, exact: exact));
    log.add('schedule:${reminder.notificationId}');
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    log.add('cancel:$id');
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    log.add('cancelAll');
  }

  @override
  Future<Set<int>> pendingIds() async => {...pending};

  @override
  Future<bool> requestPermission() async {
    requestPermissionCalls++;
    if (grantOnRequest) enabled = true;
    return enabled;
  }

  @override
  Future<bool> notificationsEnabled() async => enabled;

  @override
  Future<List<PendingReminder>> pendingReminders() async =>
      pendingReminderList ?? [for (final id in pending) PendingReminder(id: id)];

  @override
  Future<void> scheduleTest({required DateTime at}) async {
    testScheduled.add(at);
    log.add('scheduleTest');
  }

  @override
  Future<bool> canScheduleExact() async {
    canScheduleExactCalls++;
    return exactAllowed;
  }

  @override
  Future<ReminderAction?> launchAction() async => null;

  int requestExactAlarmPermissionCalls = 0;

  @override
  Future<void> requestExactAlarmPermission() async => requestExactAlarmPermissionCalls++;

  /// `until` of the last [showShieldStatus]; null while the status is cleared.
  DateTime? shieldStatusUntil;
  int showShieldStatusCalls = 0;
  int clearShieldStatusCalls = 0;

  /// When set, [showShieldStatus] and [clearShieldStatus] throw it.
  Object? throwOnShieldStatus;

  @override
  Future<void> showShieldStatus({required DateTime until}) async {
    final err = throwOnShieldStatus;
    if (err != null) {
      // Tests throw arbitrary objects on purpose.
      // ignore: only_throw_errors
      throw err;
    }
    showShieldStatusCalls++;
    shieldStatusUntil = until;
  }

  @override
  Future<void> clearShieldStatus() async {
    final err = throwOnShieldStatus;
    if (err != null) {
      // Tests throw arbitrary objects on purpose.
      // ignore: only_throw_errors
      throw err;
    }
    clearShieldStatusCalls++;
    shieldStatusUntil = null;
  }
}
