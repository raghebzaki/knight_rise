import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/time/device_timezone.dart';
import 'package:knight_rise/features/diagnostics/presentation/diagnostics_cubit.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/pending_reminder.dart';
import 'package:knight_rise/features/notifications/domain/reminder_payload.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/settings/domain/entities/app_settings.dart';

import '../../helpers/fakes.dart';
import '../../helpers/tz.dart';

class _FakeDeviceTimezone implements DeviceTimezone {
  String? id = 'Africa/Cairo';

  @override
  Future<String?> currentId() async => id;
}

PendingReminder _pending(int id, DateTime? fireAt, [Set<RoutineType> types = const {RoutineType.hydration}]) =>
    PendingReminder(
      id: id,
      payload: fireAt == null ? null : ReminderPayload(types: types, fireAt: fireAt),
    );

void main() {
  late FakeNotificationGateway gateway;
  late FakeSettingsRepository settings;
  late FakeReconcileRunRepository runs;
  late FakeScheduleReconciler reconciler;
  late _FakeDeviceTimezone deviceTz;
  late FixedClock clock;
  late DiagnosticsCubit cubit;

  setUp(() {
    gateway = FakeNotificationGateway();
    settings = FakeSettingsRepository();
    runs = FakeReconcileRunRepository();
    reconciler = FakeScheduleReconciler();
    deviceTz = _FakeDeviceTimezone();
    clock = FixedClock(at(cairo, 2026, 10, 5, 9, 30));
    cubit = DiagnosticsCubit(gateway, settings, runs, reconciler, deviceTz, clock, FakeLocationProvider(cairo));
  });

  tearDown(() => cubit.close());

  test('starts empty and not loaded', () {
    expect(cubit.state.loaded, isFalse);
    expect(cubit.state.pending, isEmpty);
  });

  test('refresh gathers status from settings, device and gateway', () async {
    await settings.save(const AppSettings(precisionTiming: true, timezoneId: 'Africa/Cairo'));
    deviceTz.id = 'Europe/Berlin';
    gateway
      ..enabled = false
      ..exactAllowed = false;

    await cubit.refresh();

    final s = cubit.state;
    expect(s.loaded, isTrue);
    expect(s.settingsTimezoneId, 'Africa/Cairo');
    expect(s.deviceTimezoneId, 'Europe/Berlin');
    expect(s.notificationsEnabled, isFalse);
    expect(s.canScheduleExact, isFalse);
    expect(s.precisionTiming, isTrue);
    expect(s.error, isNull);
  });

  test('pending reminders are sorted by fire time, payload-less last', () async {
    final t1 = at(cairo, 2026, 10, 5, 10).toUtc();
    final t2 = at(cairo, 2026, 10, 5, 11).toUtc();
    gateway.pendingReminderList = [_pending(30, null), _pending(20, t2), _pending(10, t1), _pending(5, null)];

    await cubit.refresh();

    expect(cubit.state.pending.map((p) => p.id), [10, 20, 5, 30]);
  });

  test('start streams reconcile runs (newest first) as they are recorded', () async {
    final run = ReconcileRun(at: clock.now(), trigger: ReconcileTrigger.launch, planned: 3, added: 3, cancelled: 0);
    await runs.record(run);

    await cubit.start();
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.runs, [run]);
    expect(cubit.state.loaded, isTrue);
  });

  test('reconcileNow runs a manual reconcile and refreshes', () async {
    gateway.pending = {111};
    await cubit.reconcileNow();

    expect(reconciler.calls, [ReconcileTrigger.manual]);
    expect(cubit.state.pending.map((p) => p.id), [111]);
    expect(cubit.state.busy, isFalse);
  });

  test('scheduleTest schedules the test notification one minute from now and refreshes', () async {
    gateway.pendingReminderList = [const PendingReminder(id: kTestNotificationId)];
    await cubit.scheduleTest();

    expect(gateway.testScheduled, [clock.now().add(const Duration(minutes: 1))]);
    expect(cubit.state.pending.map((p) => p.id), [kTestNotificationId]);
    expect(cubit.state.busy, isFalse);
  });

  test('a failing action surfaces the error and clears busy', () async {
    reconciler.throwOnNext = StateError('nope');
    await cubit.reconcileNow();

    expect(cubit.state.error, contains('nope'));
    expect(cubit.state.busy, isFalse);
  });

  test('toLocal expresses instants in the user zone', () {
    final utc = DateTime.utc(2026, 10, 5, 7);
    expect(cubit.toLocal(utc).hour, 10); // Cairo is UTC+3 on this date (EEST)
  });
}
