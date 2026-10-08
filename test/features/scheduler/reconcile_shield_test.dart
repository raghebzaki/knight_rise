import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/reconcile_schedule.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:knight_rise/features/work_hours/domain/usecases/day_override_usecases.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/fakes.dart';
import '../../helpers/tz.dart';

tz.TZDateTime mon(int h, [int m = 0, int s = 0]) => tz.TZDateTime(cairo, 2026, 10, 5, h, m, s);

void main() {
  late FakeRoutineRepository routines;
  late FakeWorkScheduleRepository work;
  late FakeSettingsRepository settings;
  late FakeReminderEventRepository events;
  late FakeShieldRepository shields;
  late FakeDayOverrideRepository overrides;
  late FakeNotificationGateway gateway;
  late FakeLocationProvider location;
  late FixedClock clock;
  late ReconcileSchedule reconciler;
  late StartShield startShield;
  late ExtendShield extendShield;
  late EndShield endShield;

  setUp(() {
    routines = FakeRoutineRepository();
    work = FakeWorkScheduleRepository();
    settings = FakeSettingsRepository();
    events = FakeReminderEventRepository();
    shields = FakeShieldRepository();
    overrides = FakeDayOverrideRepository();
    gateway = FakeNotificationGateway();
    location = FakeLocationProvider(cairo);
    clock = FixedClock(mon(9, 30)); // Monday, work day 09:00-17:00
    reconciler = ReconcileSchedule(
      routines,
      work,
      settings,
      events,
      shields,
      overrides,
      FakeReconcileRunRepository(),
      gateway,
      const ReminderPlanner(),
      clock,
      location,
    );
    startShield = StartShield(shields, work, overrides, const ReminderPlanner(), clock, location);
    extendShield = ExtendShield(shields, clock);
    endShield = EndShield(shields, clock);
  });

  Future<void> fullReplace() async {
    gateway
      ..scheduled.clear()
      ..cancelAllCalls = 0;
    await reconciler.reconcile(ReconcileTrigger.configChange);
  }

  List<DateTime> fireTimes() => [for (final s in gateway.scheduled) s.reminder.fireAt];
  List<DateTime> recoveries() => [
    for (final s in gateway.scheduled)
      if (s.reminder.recovery) s.reminder.fireAt,
  ];

  test('start Shield: full replace has no slots inside it and one recovery at its end', () async {
    await fullReplace();
    expect(fireTimes().any((t) => t.isAfter(mon(9, 30)) && t.isBefore(mon(10, 20))), isTrue, reason: 'baseline');

    final session = await startShield(ShieldPreset.min50); // 09:30-10:20
    expect(session, isNotNull);
    await fullReplace();

    expect(gateway.cancelAllCalls, 1);
    expect(fireTimes().where((t) => t.isBefore(mon(10, 20))), isEmpty);
    expect(recoveries(), [mon(10, 20)]);
    final recovery = gateway.scheduled.firstWhere((s) => s.reminder.recovery).reminder;
    expect(recovery.types, RoutineType.values.toSet());
  });

  test('recoverOnExit = false in settings: Shield without recovery', () async {
    await settings.save(settings.current.copyWith(shieldRecoverOnExit: false));
    await startShield(ShieldPreset.min50);
    await fullReplace();
    expect(recoveries(), isEmpty);
    expect(fireTimes().where((t) => t.isBefore(mon(10, 20))), isEmpty);
  });

  test('diff reconcile (resume) cancels stale notifications that are now inside the Shield', () async {
    await reconciler.reconcile(ReconcileTrigger.launch);
    final before = {for (final s in gateway.scheduled) s.reminder.notificationId};
    gateway
      ..pending = before
      ..scheduled.clear();

    await startShield(ShieldPreset.min50);
    final run = await reconciler.reconcile(ReconcileTrigger.resume);

    expect(run.cancelled, greaterThan(0));
    expect(gateway.cancelled, isNotEmpty);
    expect(recoveries(), [mon(10, 20)]);
  });

  test('extend: the recovery moves', () async {
    await startShield(ShieldPreset.min50); // ends 10:20
    clock.current = mon(9, 40);
    await extendShield(const Duration(minutes: 15)); // ends 10:35
    await fullReplace();
    expect(recoveries(), [mon(10, 35)]);
    expect(fireTimes().where((t) => t.isBefore(mon(10, 35))), isEmpty);
  });

  test('end early: recovery fires one minute after the end', () async {
    await startShield(ShieldPreset.min50);
    clock.current = mon(10);
    await endShield();
    clock.current = mon(10, 0, 30);
    await fullReplace();
    expect(recoveries(), [mon(10, 1)]);
    // Regular reminders are back after the end.
    expect(fireTimes().any((t) => t.isAfter(mon(10, 1))), isTrue);
  });

  test('end early: no recovery when reconciling after the +1 min moment', () async {
    await startShield(ShieldPreset.min50);
    clock.current = mon(10);
    await endShield();
    clock.current = mon(10, 5);
    await fullReplace();
    expect(recoveries(), isEmpty);
  });

  test('day off: empty plan for the rest of the day and nothing scheduled', () async {
    clock.current = tz.TZDateTime(cairo, 2026, 10, 8, 9, 30); // Thursday; Friday/Saturday are off anyway
    await fullReplace();
    expect(gateway.scheduled, isNotEmpty, reason: 'baseline');

    await SetDayOff(overrides)(DateTime.utc(2026, 10, 8));
    await fullReplace();
    expect(gateway.cancelAllCalls, 1);
    expect(gateway.scheduled, isEmpty);

    await ClearDayOverride(overrides)(DateTime.utc(2026, 10, 8));
    await fullReplace();
    expect(gateway.scheduled, isNotEmpty);
  });

  test("tomorrow's day off only affects tomorrow", () async {
    clock.current = mon(16);
    await SetDayOff(overrides)(DateTime.utc(2026, 10, 6));
    await fullReplace();
    // Nothing planned for Tuesday morning (horizon reaches Tue 16:00), none for today's evening either.
    expect(fireTimes().every((t) => t.isBefore(mon(17))), isTrue);
    expect(fireTimes(), isNotEmpty);
  });

  test('working late: extra slots appear after 17:00', () async {
    clock.current = mon(16, 30);
    await fullReplace();
    expect(fireTimes().where((t) => t.isAfter(mon(16, 59)) && t.isBefore(mon(23))), isEmpty);

    await ExtendWorkDay(overrides)(DateTime.utc(2026, 10, 5), 60);
    await fullReplace();
    final extra = fireTimes().where((t) => !t.isBefore(mon(17)) && t.isBefore(mon(18)));
    expect(extra, isNotEmpty);
    expect(fireTimes().any((t) => !t.isBefore(mon(18)) && t.isBefore(mon(23))), isFalse);
  });
  group('Shield status notification', () {
    test('shown with the Shield end while one is active, on every trigger', () async {
      await startShield(ShieldPreset.min50); // 09:30-10:20
      for (final t in [ReconcileTrigger.resume, ReconcileTrigger.configChange]) {
        gateway.shieldStatusUntil = null;
        await reconciler.reconcile(t);
        expect(gateway.shieldStatusUntil, mon(10, 20), reason: t.name);
      }
      expect(gateway.clearShieldStatusCalls, 0);
    });

    test('follows an extension and is cleared once the Shield ended', () async {
      await startShield(ShieldPreset.min25); // 09:30-09:55
      await extendShield(const Duration(minutes: 15));
      await reconciler.reconcile(ReconcileTrigger.resume);
      expect(gateway.shieldStatusUntil, mon(10, 10));

      await endShield();
      await reconciler.reconcile(ReconcileTrigger.resume);
      expect(gateway.shieldStatusUntil, isNull);
      expect(gateway.clearShieldStatusCalls, 1);
    });

    test('cleared when no Shield exists, and after the Shield expired', () async {
      await reconciler.reconcile(ReconcileTrigger.boot);
      expect(gateway.clearShieldStatusCalls, 1);

      await startShield(ShieldPreset.min25);
      clock.current = mon(10);
      await reconciler.reconcile(ReconcileTrigger.resume);
      expect(gateway.clearShieldStatusCalls, 2);
      expect(gateway.showShieldStatusCalls, 0);
    });

    test('a failing status notification does not fail the run', () async {
      await startShield(ShieldPreset.min25);
      gateway.throwOnShieldStatus = StateError('boom');
      final run = await reconciler.reconcile(ReconcileTrigger.resume);
      expect(run.error, isNull);
    });
  });
}
