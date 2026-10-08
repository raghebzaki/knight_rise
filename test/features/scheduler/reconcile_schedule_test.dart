import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/reconcile_schedule.dart';
import 'package:knight_rise/features/settings/domain/entities/app_settings.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/fakes.dart';
import '../../helpers/tz.dart';

void main() {
  late FakeRoutineRepository routines;
  late FakeWorkScheduleRepository work;
  late FakeSettingsRepository settings;
  late FakeReminderEventRepository events;
  late FakeShieldRepository shields;
  late FakeDayOverrideRepository overrides;
  late FakeReconcileRunRepository runs;
  late FakeNotificationGateway gateway;
  late FakeLocationProvider location;
  late FixedClock clock;
  late ReconcileSchedule reconciler;

  setUp(() {
    routines = FakeRoutineRepository();
    work = FakeWorkScheduleRepository();
    settings = FakeSettingsRepository();
    events = FakeReminderEventRepository();
    shields = FakeShieldRepository();
    overrides = FakeDayOverrideRepository();
    runs = FakeReconcileRunRepository();
    gateway = FakeNotificationGateway();
    location = FakeLocationProvider(cairo);
    // Monday 2026-10-05 is a work day (Sun-Thu 09:00-17:00).
    clock = FixedClock(at(cairo, 2026, 10, 5, 9, 30));
    reconciler = ReconcileSchedule(
      routines,
      work,
      settings,
      events,
      shields,
      overrides,
      runs,
      gateway,
      const ReminderPlanner(),
      clock,
      location,
    );
  });

  Set<int> scheduledIds() => {for (final s in gateway.scheduled) s.reminder.notificationId};

  test('empty OS: schedules the full plan and records the run', () async {
    final run = await reconciler.reconcile(ReconcileTrigger.launch);

    expect(run.planned, greaterThan(0));
    expect(run.planned, lessThanOrEqualTo(50));
    expect(run.added, run.planned);
    expect(run.cancelled, 0);
    expect(run.error, isNull);
    expect(run.trigger, ReconcileTrigger.launch);
    expect(run.at, clock.now());
    expect(gateway.scheduled.length, run.planned);
    expect(gateway.cancelled, isEmpty);
    expect(gateway.cancelAllCalls, 0);
    expect(runs.runs.single, run);
  });

  test('second identical reconcile is idempotent', () async {
    await reconciler.reconcile(ReconcileTrigger.launch);
    gateway
      ..pending = scheduledIds()
      ..scheduled.clear();

    final run = await reconciler.reconcile(ReconcileTrigger.resume);

    expect(run.added, 0);
    expect(run.cancelled, 0);
    expect(run.planned, gateway.pending.length);
    expect(gateway.scheduled, isEmpty);
    expect(gateway.cancelled, isEmpty);
  });

  test('after a Done at 09:50 stale hydration slots are cancelled and new ones added', () async {
    await reconciler.reconcile(ReconcileTrigger.launch);
    final firstPlan = [for (final s in gateway.scheduled) s.reminder];
    gateway
      ..pending = scheduledIds()
      ..scheduled.clear();

    clock.current = at(cairo, 2026, 10, 5, 9, 50);
    await events.add(
      ReminderEvent(type: RoutineType.hydration, outcome: ReminderOutcome.done, at: clock.now(), waterMl: 250),
    );
    final run = await reconciler.reconcile(ReconcileTrigger.action);

    final newIds = scheduledIds();
    final kept = gateway.pending.difference(gateway.cancelled.toSet());
    expect(run.added, newIds.length);
    expect(run.added, greaterThan(0));
    expect(run.cancelled, gateway.cancelled.length);
    expect(run.cancelled, greaterThan(0));
    expect(gateway.pending.containsAll(gateway.cancelled), isTrue);
    expect(kept.length + newIds.length, run.planned);
    expect(newIds.intersection(gateway.pending), isEmpty);
    // Stale hydration slots are among those cancelled (neighbours may also be re-merged).
    final byId = {for (final r in firstPlan) r.notificationId: r};
    expect(gateway.cancelled.any((id) => byId[id]!.types.contains(RoutineType.hydration)), isTrue);
    // New slots are anchored to the completion: first hydration at 09:50 + 45 min.
    final hydration = gateway.scheduled.map((s) => s.reminder).where((r) => r.types.contains(RoutineType.hydration));
    expect(hydration.first.fireAt.isAtSameMomentAs(at(cairo, 2026, 10, 5, 10, 35)), isTrue);
    expect(gateway.cancelAllCalls, 0);
  });

  for (final trigger in [ReconcileTrigger.configChange, ReconcileTrigger.timezoneChange, ReconcileTrigger.boot]) {
    test('${trigger.name} cancels all pending, then schedules everything', () async {
      await reconciler.reconcile(ReconcileTrigger.launch);
      gateway
        ..pending = scheduledIds()
        ..scheduled.clear()
        ..log.clear();
      final pendingCount = gateway.pending.length;

      final run = await reconciler.reconcile(trigger);

      expect(gateway.cancelAllCalls, 1);
      expect(gateway.cancelled, isEmpty);
      expect(run.cancelled, pendingCount);
      expect(run.added, run.planned);
      expect(gateway.scheduled.length, run.planned);
      expect(gateway.log.first, 'cancelAll');
      expect(gateway.log.skip(1).every((l) => l.startsWith('schedule:')), isTrue);
    });
  }

  group('reserved diagnostics ids (< 1000)', () {
    test('diff path never cancels them, but still cancels stale planner ids', () async {
      const staleId = 123456;
      gateway.pending = {kTestNotificationId, 999, staleId};

      final run = await reconciler.reconcile(ReconcileTrigger.manual);

      expect(gateway.cancelled, [staleId]);
      expect(run.cancelled, 1);
      expect(run.trigger, ReconcileTrigger.manual);
    });

    test('ids at the limit are ordinary planner ids', () async {
      gateway.pending = {kReservedNotificationIdLimit};
      await reconciler.reconcile(ReconcileTrigger.resume);
      expect(gateway.cancelled, [kReservedNotificationIdLimit]);
    });

    test('full-replace triggers still clear them', () async {
      gateway.pending = {kTestNotificationId};
      final run = await reconciler.reconcile(ReconcileTrigger.configChange);
      expect(gateway.cancelAllCalls, 1);
      expect(run.cancelled, 1);
    });
  });

  group('exact alarms', () {
    test('precisionTiming on but not permitted -> inexact everywhere', () async {
      await settings.save(const AppSettings(precisionTiming: true));
      gateway.exactAllowed = false;
      await reconciler.reconcile(ReconcileTrigger.launch);
      expect(gateway.scheduled, isNotEmpty);
      expect(gateway.scheduled.every((s) => !s.exact), isTrue);
      expect(gateway.canScheduleExactCalls, 1);
    });

    test('precisionTiming on and permitted -> exact everywhere, checked once', () async {
      await settings.save(const AppSettings(precisionTiming: true));
      await reconciler.reconcile(ReconcileTrigger.launch);
      expect(gateway.scheduled.length, greaterThan(1));
      expect(gateway.scheduled.every((s) => s.exact), isTrue);
      expect(gateway.canScheduleExactCalls, 1);
    });

    test('precisionTiming off -> inexact', () async {
      await reconciler.reconcile(ReconcileTrigger.launch);
      expect(gateway.scheduled.every((s) => !s.exact), isTrue);
    });
  });

  test('location is read from the provider at run time', () async {
    await reconciler.reconcile(ReconcileTrigger.launch);
    expect(gateway.scheduled.map((s) => (s.reminder.fireAt as tz.TZDateTime).location), everyElement(cairo));

    location.location = newYork;
    gateway.scheduled.clear();
    final run = await reconciler.reconcile(ReconcileTrigger.timezoneChange);

    expect(run.error, isNull);
    expect(gateway.scheduled, isNotEmpty);
    expect(gateway.scheduled.map((s) => (s.reminder.fireAt as tz.TZDateTime).location), everyElement(newYork));
  });

  test('gateway failure is recorded, never thrown', () async {
    gateway.throwOnSchedule = StateError('boom');
    final run = await reconciler.reconcile(ReconcileTrigger.launch);

    expect(run.error, contains('boom'));
    expect(run.planned, greaterThan(0));
    expect(run.added, 0);
    expect(runs.runs.single, run);
  });

  test('records run then prunes to 200', () async {
    await reconciler.reconcile(ReconcileTrigger.launch);
    expect(runs.pruneKeeps, [200]);
    gateway.throwOnSchedule = StateError('x');
    await reconciler.reconcile(ReconcileTrigger.launch);
    expect(runs.pruneKeeps, [200, 200]);
  });

  test('never writes reminder events', () async {
    await reconciler.reconcile(ReconcileTrigger.launch);
    await reconciler.reconcile(ReconcileTrigger.configChange);
    expect(events.all, isEmpty);
  });
}
