// Milestone 3 gate: end-to-end schedule scenarios.
//
// Everything below the OS boundary is real: an in-memory Drift database, the
// Drift repositories, the real use cases (Shield, day overrides, Done/Snooze),
// `ReconcileSchedule` and `ReminderPlanner`. Only the clock (FixedClock, Cairo)
// and the notification scheduler ([OsNotificationSimulator]) are simulated.
//
// Every scenario spells out the exact expected pending schedule. Format of an
// entry: `[Day ]HH:MM type+type[ (recovery)]`, local Cairo time, day prefix only
// for days other than Monday 2026-10-05. Types are in routine order
// (hydration, stretch, eyeRest).
//
// Defaults: Sun-Thu 09:00-17:00, hydration 45 min, stretch 60 min, eye rest
// 20 min, 5-minute merge window, 24 h planning horizon, 50 notification cap.
// Routines are rolling and anchor to the work-window start, so a reminder that
// has already passed is never re-fired; a Shield only suppresses slots that
// still lie ahead.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/routines/data/drift_routine_repository.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/data/drift_reconcile_run_repository.dart';
import 'package:knight_rise/features/scheduler/data/drift_reminder_event_repository.dart';
import 'package:knight_rise/features/scheduler/domain/entities/cycle_snapshot.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/handle_reminder_action.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/reconcile_schedule.dart';
import 'package:knight_rise/features/settings/data/drift_settings_repository.dart';
import 'package:knight_rise/features/shield/data/drift_shield_repository.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:knight_rise/features/work_hours/data/drift_day_override_repository.dart';
import 'package:knight_rise/features/work_hours/data/drift_work_schedule_repository.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:knight_rise/features/work_hours/domain/usecases/day_override_usecases.dart';
import 'package:timezone/timezone.dart' as tz;

import '../helpers/fakes.dart';
import '../helpers/tz.dart';
import 'os_simulator.dart';

tz.TZDateTime mon(int h, [int m = 0]) => tz.TZDateTime(cairo, 2026, 10, 5, h, m);

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _two(int n) => n.toString().padLeft(2, '0');

String _typesLabel(Set<RoutineType> types) =>
    (types.toList()..sort((a, b) => a.index.compareTo(b.index))).map((t) => t.name).join('+');

/// `[Day ]HH:MM types[ (recovery)]` in Cairo local time.
String describe(DateTime fireAt, Set<RoutineType> types, {bool recovery = false}) {
  final l = tz.TZDateTime.from(fireAt, cairo);
  final day = l.day == 5 && l.month == 10 ? '' : '${_dayNames[l.weekday - 1]} ';
  return '$day${_two(l.hour)}:${_two(l.minute)} ${_typesLabel(types)}${recovery ? ' (recovery)' : ''}';
}

String describePlanned(PlannedReminder r) => describe(r.fireAt, r.types, recovery: r.recovery);

/// The whole app (minus the OS) wired exactly as production wires it.
class Gate {
  Gate._(this.db, this.clock, this.os) {
    routines = DriftRoutineRepository(db);
    work = DriftWorkScheduleRepository(db);
    settings = DriftSettingsRepository(db);
    events = DriftReminderEventRepository(db);
    shields = DriftShieldRepository(db);
    overrides = DriftDayOverrideRepository(db);
    final location = FakeLocationProvider(cairo);
    reconciler = ReconcileSchedule(
      routines,
      work,
      settings,
      events,
      shields,
      overrides,
      DriftReconcileRunRepository(db),
      os,
      planner,
      clock,
      location,
    );
    startShield = StartShield(shields, work, overrides, planner, clock, location);
    extendShield = ExtendShield(shields, clock);
    endShield = EndShield(shields, clock);
    setDayOff = SetDayOff(overrides);
    extendWorkDay = ExtendWorkDay(overrides);
    clearDayOverride = ClearDayOverride(overrides);
    handle = HandleReminderAction(
      CompleteRoutine(events, settings, clock),
      SnoozeRoutine(events, clock, cairo),
      reconciler,
      endShield,
    );
  }

  /// A fresh in-memory database (seeded with the default routines, Sun-Thu
  /// 09:00-17:00 and default settings) with the clock at [start].
  factory Gate.create(tz.TZDateTime start) {
    final clock = FixedClock(start);
    return Gate._(AppDatabase(NativeDatabase.memory()), clock, OsNotificationSimulator(clock));
  }

  final AppDatabase db;
  final FixedClock clock;
  final OsNotificationSimulator os;
  final planner = const ReminderPlanner();

  late final DriftRoutineRepository routines;
  late final DriftWorkScheduleRepository work;
  late final DriftSettingsRepository settings;
  late final DriftReminderEventRepository events;
  late final DriftShieldRepository shields;
  late final DriftDayOverrideRepository overrides;
  late final ReconcileSchedule reconciler;
  late final StartShield startShield;
  late final ExtendShield extendShield;
  late final EndShield endShield;
  late final SetDayOff setDayOff;
  late final ExtendWorkDay extendWorkDay;
  late final ClearDayOverride clearDayOverride;
  late final HandleReminderAction handle;

  Future<void> close() => db.close();

  /// Production calls `reconcile(trigger)` after every user action; a failed
  /// run would be swallowed into the audit log, so the gate fails loudly.
  Future<ReconcileRun> reconcile(ReconcileTrigger trigger) async {
    final run = await reconciler.reconcile(trigger);
    expect(run.error, isNull, reason: 'reconcile(${trigger.name}) must not fail');
    return run;
  }

  /// Moves time forward; the OS delivers what is due.
  void advanceTo(tz.TZDateTime t) => os.advanceTo(t);

  DateTime get today => localDateOf(clock.now(), cairo);

  /// What the OS holds that this app planned (reserved diagnostics ids excluded).
  Future<List<PlannedPending>> plannedPending() async {
    final all = await os.pendingReminders();
    return [
      for (final p in all)
        if (p.id >= kReservedNotificationIdLimit && p.payload != null)
          PlannedPending(p.id, p.payload!.fireAt, p.payload!.types, recovery: p.payload!.recovery),
    ];
  }

  Future<List<String>> pending() async => [
    for (final p in await plannedPending()) describe(p.fireAt, p.types, recovery: p.recovery),
  ];

  /// Asserts the exact pending schedule, in time order.
  Future<void> expectPending(List<String> expected, {String? reason}) async {
    expect(await pending(), expected, reason: reason);
  }

  Future<List<PlannedPending>> recoveries() async => [
    for (final p in await plannedPending())
      if (p.recovery) p,
  ];

  /// Two consecutive resume reconciles: the schedule is a fixed point.
  Future<void> expectIdempotent() async {
    await reconcile(ReconcileTrigger.resume);
    final settled = await os.pendingIds();
    final second = await reconcile(ReconcileTrigger.resume);
    expect(second.added, 0, reason: 'second resume reconcile must add nothing');
    expect(second.cancelled, 0, reason: 'second resume reconcile must cancel nothing');
    expect(await os.pendingIds(), settled);
  }

  /// The dashboard's view of the world, built from the real repositories.
  Future<CycleSnapshot> snapshot() async {
    final now = clock.now();
    final dayStart = startOfLocalDay(now, cairo);
    final inputs = CycleInputs(
      routines: await routines.getAll(),
      schedule: await work.get(),
      todayEvents: await events.getSince(dayStart),
      settings: await settings.get(),
      shields: await shields.getSince(dayStart),
      overrides: await overrides.getFrom(localDateOf(now, cairo)),
    );
    return BuildCycleSnapshot(planner)(inputs, now: now, location: cairo);
  }

  /// Replaces Monday's windows (the work-hours editor's save).
  Future<void> saveMonday(List<TimeWindow> windows) async {
    final current = await work.get();
    await work.save(WorkSchedule(days: {...current.days, DateTime.monday: windows}));
  }

  Future<List<ReminderEvent>> todaysEvents() => events.getSince(startOfLocalDay(clock.now(), cairo));
}

class PlannedPending {
  const PlannedPending(this.id, this.fireAt, this.types, {required this.recovery});

  final int id;
  final DateTime fireAt;
  final Set<RoutineType> types;
  final bool recovery;
}

/// Monday 2026-10-05 with the default routines and Sun-Thu 09:00-17:00, no Shield.
const _mondayPlan = [
  '09:20 eyeRest',
  '09:40 hydration+eyeRest',
  '10:00 stretch+eyeRest',
  '10:20 eyeRest',
  '10:30 hydration',
  '10:40 eyeRest',
  '11:00 stretch+eyeRest',
  '11:15 hydration+eyeRest',
  '11:40 eyeRest',
  '12:00 hydration+stretch+eyeRest',
  '12:20 eyeRest',
  '12:40 hydration+eyeRest',
  '13:00 stretch+eyeRest',
  '13:20 eyeRest',
  '13:30 hydration',
  '13:40 eyeRest',
  '14:00 stretch+eyeRest',
  '14:15 hydration+eyeRest',
  '14:40 eyeRest',
  '15:00 hydration+stretch+eyeRest',
  '15:20 eyeRest',
  '15:40 hydration+eyeRest',
  '16:00 stretch+eyeRest',
  '16:20 eyeRest',
  '16:30 hydration',
  '16:40 eyeRest',
];

bool _inRange(DateTime t, DateTime from, DateTime toExclusive) => !t.isBefore(from) && t.isBefore(toExclusive);

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late Gate g;
  tearDown(() => g.close());

  group('M3 gate', () {
    test('1. baseline at 09:00: the full day plan', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);

      final plan = await g.pending();
      expect(plan, hasLength(26));
      // First six entries, spelled out.
      expect(plan.take(6), [
        '09:20 eyeRest',
        '09:40 hydration+eyeRest',
        '10:00 stretch+eyeRest',
        '10:20 eyeRest',
        '10:30 hydration',
        '10:40 eyeRest',
      ]);
      await g.expectPending([
        '09:20 eyeRest',
        '09:40 hydration+eyeRest',
        '10:00 stretch+eyeRest',
        '10:20 eyeRest',
        '10:30 hydration',
        '10:40 eyeRest',
        '11:00 stretch+eyeRest',
        '11:15 hydration+eyeRest',
        '11:40 eyeRest',
        '12:00 hydration+stretch+eyeRest',
        '12:20 eyeRest',
        '12:40 hydration+eyeRest',
        '13:00 stretch+eyeRest',
        '13:20 eyeRest',
        '13:30 hydration',
        '13:40 eyeRest',
        '14:00 stretch+eyeRest',
        '14:15 hydration+eyeRest',
        '14:40 eyeRest',
        '15:00 hydration+stretch+eyeRest',
        '15:20 eyeRest',
        '15:40 hydration+eyeRest',
        '16:00 stretch+eyeRest',
        '16:20 eyeRest',
        '16:30 hydration',
        '16:40 eyeRest',
      ]);
      expect(g.os.shieldStatusShown, isFalse);
      await g.expectIdempotent();
    });

    test('2. 25 min Shield at 10:05: silence, one recovery at 10:30, status shown then cleared', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);
      g.advanceTo(mon(10, 5));
      await g.reconcile(ReconcileTrigger.resume);

      await g.startShield(ShieldPreset.min25);
      await g.reconcile(ReconcileTrigger.configChange);

      await g.expectPending([
        '10:30 hydration+eyeRest (recovery)',
        '10:40 eyeRest',
        '11:00 stretch+eyeRest',
        '11:15 hydration+eyeRest',
        '11:40 eyeRest',
        '12:00 hydration+stretch+eyeRest',
        '12:20 eyeRest',
        '12:40 hydration+eyeRest',
        '13:00 stretch+eyeRest',
        '13:20 eyeRest',
        '13:30 hydration',
        '13:40 eyeRest',
        '14:00 stretch+eyeRest',
        '14:15 hydration+eyeRest',
        '14:40 eyeRest',
        '15:00 hydration+stretch+eyeRest',
        '15:20 eyeRest',
        '15:40 hydration+eyeRest',
        '16:00 stretch+eyeRest',
        '16:20 eyeRest',
        '16:30 hydration',
        '16:40 eyeRest',
        'Tue 09:20 eyeRest',
        'Tue 09:40 hydration+eyeRest',
        'Tue 10:00 stretch+eyeRest',
      ]);
      final all = await g.plannedPending();
      expect(all.where((p) => _inRange(p.fireAt, mon(10, 5), mon(10, 30))), isEmpty);
      // Only eye rest (10:20) was held back: hydration's 10:30 slot is at the
      // Shield's exclusive end, stretch's 10:00 slot is before it. The 10:30
      // hydration slot merges into the recovery (same minute).
      final recovery = (await g.recoveries()).single;
      expect(recovery.fireAt.isAtSameMomentAs(mon(10, 30)), isTrue);
      expect(recovery.types, {RoutineType.hydration, RoutineType.eyeRest});
      expect(g.os.shieldStatusUntil!.isAtSameMomentAs(mon(10, 30)), isTrue);

      // The Shield ends by itself; the OS delivers the recovery.
      g.advanceTo(mon(10, 31));
      expect(g.os.shieldStatusShown, isTrue, reason: 'nothing cleared it yet');
      await g.reconcile(ReconcileTrigger.resume);

      expect(g.os.shieldStatusShown, isFalse);
      await g.expectPending([
        '10:40 eyeRest',
        '11:00 stretch+eyeRest',
        '11:15 hydration+eyeRest',
        '11:40 eyeRest',
        '12:00 hydration+stretch+eyeRest',
        '12:20 eyeRest',
        '12:40 hydration+eyeRest',
        '13:00 stretch+eyeRest',
        '13:20 eyeRest',
        '13:30 hydration',
        '13:40 eyeRest',
        '14:00 stretch+eyeRest',
        '14:15 hydration+eyeRest',
        '14:40 eyeRest',
        '15:00 hydration+stretch+eyeRest',
        '15:20 eyeRest',
        '15:40 hydration+eyeRest',
        '16:00 stretch+eyeRest',
        '16:20 eyeRest',
        '16:30 hydration',
        '16:40 eyeRest',
        'Tue 09:20 eyeRest',
        'Tue 09:40 hydration+eyeRest',
        'Tue 10:00 stretch+eyeRest',
        'Tue 10:20 eyeRest',
        'Tue 10:30 hydration',
      ]);
      expect(g.os.delivered.map(describePlanned), [
        '09:20 eyeRest',
        '09:40 hydration+eyeRest',
        '10:00 stretch+eyeRest',
        '10:30 hydration+eyeRest (recovery)',
      ]);
      await g.expectIdempotent();
    });

    test('3. extend +15: the recovery moves to 10:45 and nothing fires in [10:05, 10:45)', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);
      g.advanceTo(mon(10, 5));
      await g.startShield(ShieldPreset.min25);
      await g.reconcile(ReconcileTrigger.configChange);

      g.advanceTo(mon(10, 8));
      await g.extendShield(const Duration(minutes: 15));
      await g.reconcile(ReconcileTrigger.configChange);

      await g.expectPending([
        '10:45 hydration+eyeRest (recovery)',
        '11:00 stretch+eyeRest',
        '11:15 hydration+eyeRest',
        '11:40 eyeRest',
        '12:00 hydration+stretch+eyeRest',
        '12:20 eyeRest',
        '12:40 hydration+eyeRest',
        '13:00 stretch+eyeRest',
        '13:20 eyeRest',
        '13:30 hydration',
        '13:40 eyeRest',
        '14:00 stretch+eyeRest',
        '14:15 hydration+eyeRest',
        '14:40 eyeRest',
        '15:00 hydration+stretch+eyeRest',
        '15:20 eyeRest',
        '15:40 hydration+eyeRest',
        '16:00 stretch+eyeRest',
        '16:20 eyeRest',
        '16:30 hydration',
        '16:40 eyeRest',
        'Tue 09:20 eyeRest',
        'Tue 09:40 hydration+eyeRest',
        'Tue 10:00 stretch+eyeRest',
      ]);
      expect((await g.plannedPending()).where((p) => _inRange(p.fireAt, mon(10, 5), mon(10, 45))), isEmpty);
      final recovery = (await g.recoveries()).single;
      expect(recovery.fireAt.isAtSameMomentAs(mon(10, 45)), isTrue);
      // Held back: hydration 10:30, eye rest 10:20 and 10:40.
      expect(recovery.types, {RoutineType.hydration, RoutineType.eyeRest});
      expect(g.os.shieldStatusUntil!.isAtSameMomentAs(mon(10, 45)), isTrue);
      await g.expectIdempotent();
    });

    test('4a. end early at 10:15 while nothing was held back: no recovery, status cleared', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);
      g.advanceTo(mon(10, 5));
      await g.startShield(ShieldPreset.min25);
      await g.reconcile(ReconcileTrigger.configChange);
      expect(g.os.shieldStatusShown, isTrue);

      g.advanceTo(mon(10, 15));
      await g.endShield();
      await g.reconcile(ReconcileTrigger.configChange);

      // No slot lies inside [10:05, 10:15) (the next one is eye rest at 10:20).
      // The recovery rule is "only routines with a slot suppressed inside the
      // Shield", so there is nothing to recover.
      await g.expectPending([
        '10:20 eyeRest',
        '10:30 hydration',
        '10:40 eyeRest',
        '11:00 stretch+eyeRest',
        '11:15 hydration+eyeRest',
        '11:40 eyeRest',
        '12:00 hydration+stretch+eyeRest',
        '12:20 eyeRest',
        '12:40 hydration+eyeRest',
        '13:00 stretch+eyeRest',
        '13:20 eyeRest',
        '13:30 hydration',
        '13:40 eyeRest',
        '14:00 stretch+eyeRest',
        '14:15 hydration+eyeRest',
        '14:40 eyeRest',
        '15:00 hydration+stretch+eyeRest',
        '15:20 eyeRest',
        '15:40 hydration+eyeRest',
        '16:00 stretch+eyeRest',
        '16:20 eyeRest',
        '16:30 hydration',
        '16:40 eyeRest',
        'Tue 09:20 eyeRest',
        'Tue 09:40 hydration+eyeRest',
        'Tue 10:00 stretch+eyeRest',
      ]);
      expect(await g.recoveries(), isEmpty);
      expect(g.os.shieldStatusShown, isFalse);
      await g.expectIdempotent();
    });

    test('4b. end early at 10:25 after eye rest was held back: recovery at 10:26, status cleared', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);
      g.advanceTo(mon(10, 5));
      await g.startShield(ShieldPreset.min25);
      await g.reconcile(ReconcileTrigger.configChange);

      g.advanceTo(mon(10, 25));
      await g.endShield();
      await g.reconcile(ReconcileTrigger.configChange);

      // The 10:30 hydration slot is within 5 minutes of the 10:26 recovery and
      // is merged into it.
      await g.expectPending([
        '10:26 hydration+eyeRest (recovery)',
        '10:40 eyeRest',
        '11:00 stretch+eyeRest',
        '11:15 hydration+eyeRest',
        '11:40 eyeRest',
        '12:00 hydration+stretch+eyeRest',
        '12:20 eyeRest',
        '12:40 hydration+eyeRest',
        '13:00 stretch+eyeRest',
        '13:20 eyeRest',
        '13:30 hydration',
        '13:40 eyeRest',
        '14:00 stretch+eyeRest',
        '14:15 hydration+eyeRest',
        '14:40 eyeRest',
        '15:00 hydration+stretch+eyeRest',
        '15:20 eyeRest',
        '15:40 hydration+eyeRest',
        '16:00 stretch+eyeRest',
        '16:20 eyeRest',
        '16:30 hydration',
        '16:40 eyeRest',
        'Tue 09:20 eyeRest',
        'Tue 09:40 hydration+eyeRest',
        'Tue 10:00 stretch+eyeRest',
        'Tue 10:20 eyeRest',
      ]);
      final recovery = (await g.recoveries()).single;
      expect(recovery.fireAt.isAtSameMomentAs(mon(10, 26)), isTrue);
      expect(g.os.shieldStatusShown, isFalse);
      await g.expectIdempotent();
    });

    test('5a. Shield while hydration is Due (09:50, 50 min): status Shielded, recovery covers all three', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);
      g.advanceTo(mon(9, 50));
      await g.reconcile(ReconcileTrigger.resume);

      var hydration = (await g.snapshot()).viewOf(RoutineType.hydration)!;
      expect(hydration.status, isA<StatusDue>());
      expect((hydration.status as StatusDue).since.isAtSameMomentAs(mon(9, 45)), isTrue);

      await g.startShield(ShieldPreset.min50); // 09:50-10:40
      await g.reconcile(ReconcileTrigger.configChange);

      hydration = (await g.snapshot()).viewOf(RoutineType.hydration)!;
      expect(hydration.status, isA<StatusShielded>());
      expect((hydration.status as StatusShielded).until.isAtSameMomentAs(mon(10, 40)), isTrue);

      // Planner rule: a routine is in the recovery only when a slot of it lies
      // inside the Shield. Hydration's 09:45 slot is before the Shield, but its
      // 10:30 slot is inside, so it is included (with stretch 10:00 and eye
      // rest). The regular 10:40 eye rest slot merges into the recovery.
      await g.expectPending([
        '10:40 hydration+stretch+eyeRest (recovery)',
        '11:00 stretch+eyeRest',
        '11:15 hydration+eyeRest',
        '11:40 eyeRest',
        '12:00 hydration+stretch+eyeRest',
        '12:20 eyeRest',
        '12:40 hydration+eyeRest',
        '13:00 stretch+eyeRest',
        '13:20 eyeRest',
        '13:30 hydration',
        '13:40 eyeRest',
        '14:00 stretch+eyeRest',
        '14:15 hydration+eyeRest',
        '14:40 eyeRest',
        '15:00 hydration+stretch+eyeRest',
        '15:20 eyeRest',
        '15:40 hydration+eyeRest',
        '16:00 stretch+eyeRest',
        '16:20 eyeRest',
        '16:30 hydration',
        '16:40 eyeRest',
        'Tue 09:20 eyeRest',
        'Tue 09:40 hydration+eyeRest',
      ]);
      final recovery = (await g.recoveries()).single;
      expect(recovery.types, RoutineType.values.toSet());
      expect(g.os.shieldStatusUntil!.isAtSameMomentAs(mon(10, 40)), isTrue);
      await g.expectIdempotent();
    });

    test('5b. same start with a 25 min Shield: hydration has no slot inside, so it is not in the recovery', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);
      g.advanceTo(mon(9, 50));
      await g.reconcile(ReconcileTrigger.resume);

      await g.startShield(ShieldPreset.min25); // 09:50-10:15
      await g.reconcile(ReconcileTrigger.configChange);

      final hydration = (await g.snapshot()).viewOf(RoutineType.hydration)!;
      expect(hydration.status, isA<StatusShielded>(), reason: 'Shielded outranks Due');
      await g.expectPending([
        '10:15 stretch+eyeRest (recovery)',
        '10:30 hydration',
        '10:40 eyeRest',
        '11:00 stretch+eyeRest',
        '11:15 hydration+eyeRest',
        '11:40 eyeRest',
        '12:00 hydration+stretch+eyeRest',
        '12:20 eyeRest',
        '12:40 hydration+eyeRest',
        '13:00 stretch+eyeRest',
        '13:20 eyeRest',
        '13:30 hydration',
        '13:40 eyeRest',
        '14:00 stretch+eyeRest',
        '14:15 hydration+eyeRest',
        '14:40 eyeRest',
        '15:00 hydration+stretch+eyeRest',
        '15:20 eyeRest',
        '15:40 hydration+eyeRest',
        '16:00 stretch+eyeRest',
        '16:20 eyeRest',
        '16:30 hydration',
        '16:40 eyeRest',
        'Tue 09:20 eyeRest',
        'Tue 09:40 hydration+eyeRest',
      ]);
      final recovery = (await g.recoveries()).single;
      expect(recovery.types, {RoutineType.stretch, RoutineType.eyeRest});
      await g.expectIdempotent();
    });

    test('6. "until I turn it off" at 15:00: silent until 17:00, no recovery, status until 17:00', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);
      g.advanceTo(mon(15));
      await g.reconcile(ReconcileTrigger.resume);

      final session = await g.startShield(ShieldPreset.untilOff);
      expect(session!.endAt.isAtSameMomentAs(mon(17)), isTrue);
      await g.reconcile(ReconcileTrigger.configChange);

      // Nothing for the rest of Monday; the horizon (24 h) reaches into Tuesday.
      await g.expectPending([
        'Tue 09:20 eyeRest',
        'Tue 09:40 hydration+eyeRest',
        'Tue 10:00 stretch+eyeRest',
        'Tue 10:20 eyeRest',
        'Tue 10:30 hydration',
        'Tue 10:40 eyeRest',
        'Tue 11:00 stretch+eyeRest',
        'Tue 11:15 hydration+eyeRest',
        'Tue 11:40 eyeRest',
        'Tue 12:00 hydration+stretch+eyeRest',
        'Tue 12:20 eyeRest',
        'Tue 12:40 hydration+eyeRest',
        'Tue 13:00 stretch+eyeRest',
        'Tue 13:20 eyeRest',
        'Tue 13:30 hydration',
        'Tue 13:40 eyeRest',
        'Tue 14:00 stretch+eyeRest',
        'Tue 14:15 hydration+eyeRest',
        'Tue 14:40 eyeRest',
        'Tue 15:00 hydration+stretch+eyeRest',
      ]);
      expect((await g.plannedPending()).where((p) => p.fireAt.isBefore(tz.TZDateTime(cairo, 2026, 10, 6))), isEmpty);
      expect(await g.recoveries(), isEmpty, reason: '17:00 is the end of the work window');
      expect(g.os.shieldStatusUntil!.isAtSameMomentAs(mon(17)), isTrue);
      await g.expectIdempotent();
    });

    test(
      '7. overlapping Shields (25 min at 10:00, then 50 min at 10:10): one merged window, one recovery at 11:00',
      () async {
        g = Gate.create(mon(9));
        await g.reconcile(ReconcileTrigger.launch);
        g.advanceTo(mon(10));
        await g.startShield(ShieldPreset.min25);
        await g.reconcile(ReconcileTrigger.configChange);

        g.advanceTo(mon(10, 10));
        await g.startShield(ShieldPreset.min50);
        await g.reconcile(ReconcileTrigger.configChange);

        final sessions = await g.shields.getSince(mon(0));
        expect(sessions, hasLength(2));
        expect(sessions.first.endedEarly, isTrue, reason: 'the first Shield was replaced at 10:10');

        await g.expectPending([
          '11:00 hydration+stretch+eyeRest (recovery)',
          '11:15 hydration+eyeRest',
          '11:40 eyeRest',
          '12:00 hydration+stretch+eyeRest',
          '12:20 eyeRest',
          '12:40 hydration+eyeRest',
          '13:00 stretch+eyeRest',
          '13:20 eyeRest',
          '13:30 hydration',
          '13:40 eyeRest',
          '14:00 stretch+eyeRest',
          '14:15 hydration+eyeRest',
          '14:40 eyeRest',
          '15:00 hydration+stretch+eyeRest',
          '15:20 eyeRest',
          '15:40 hydration+eyeRest',
          '16:00 stretch+eyeRest',
          '16:20 eyeRest',
          '16:30 hydration',
          '16:40 eyeRest',
          'Tue 09:20 eyeRest',
          'Tue 09:40 hydration+eyeRest',
          'Tue 10:00 stretch+eyeRest',
        ]);
        final recovery = (await g.recoveries()).single;
        expect(recovery.fireAt.isAtSameMomentAs(mon(11)), isTrue);
        expect(recovery.types, RoutineType.values.toSet());
        expect((await g.plannedPending()).where((p) => _inRange(p.fireAt, mon(10, 10), mon(11))), isEmpty);
        expect(g.os.shieldStatusUntil!.isAtSameMomentAs(mon(11)), isTrue);
        await g.expectIdempotent();
      },
    );

    test('8. recovery disabled in settings: Shield without any recovery entry', () async {
      g = Gate.create(mon(9));
      await g.settings.save((await g.settings.get()).copyWith(shieldRecoverOnExit: false));
      await g.reconcile(ReconcileTrigger.launch);
      g.advanceTo(mon(10, 5));
      await g.startShield(ShieldPreset.min25);
      await g.reconcile(ReconcileTrigger.configChange);

      await g.expectPending([
        '10:30 hydration',
        '10:40 eyeRest',
        '11:00 stretch+eyeRest',
        '11:15 hydration+eyeRest',
        '11:40 eyeRest',
        '12:00 hydration+stretch+eyeRest',
        '12:20 eyeRest',
        '12:40 hydration+eyeRest',
        '13:00 stretch+eyeRest',
        '13:20 eyeRest',
        '13:30 hydration',
        '13:40 eyeRest',
        '14:00 stretch+eyeRest',
        '14:15 hydration+eyeRest',
        '14:40 eyeRest',
        '15:00 hydration+stretch+eyeRest',
        '15:20 eyeRest',
        '15:40 hydration+eyeRest',
        '16:00 stretch+eyeRest',
        '16:20 eyeRest',
        '16:30 hydration',
        '16:40 eyeRest',
        'Tue 09:20 eyeRest',
        'Tue 09:40 hydration+eyeRest',
        'Tue 10:00 stretch+eyeRest',
      ]);
      expect(await g.recoveries(), isEmpty);
      expect(g.os.shieldStatusUntil!.isAtSameMomentAs(mon(10, 30)), isTrue);
      await g.expectIdempotent();
    });

    test('9. work-hours edit: Monday 10:00-14:00 + 15:00-18:00 leaves the gap empty', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);
      expect(await g.pending(), hasLength(26));

      await g.saveMonday([TimeWindow.hm(10, 0, 14, 0), TimeWindow.hm(15, 0, 18, 0)]);
      await g.reconcile(ReconcileTrigger.configChange);

      await g.expectPending([
        '10:20 eyeRest',
        '10:40 hydration+eyeRest',
        '11:00 stretch+eyeRest',
        '11:20 eyeRest',
        '11:30 hydration',
        '11:40 eyeRest',
        '12:00 stretch+eyeRest',
        '12:15 hydration+eyeRest',
        '12:40 eyeRest',
        '13:00 hydration+stretch+eyeRest',
        '13:20 eyeRest',
        '13:40 hydration+eyeRest',
        '15:20 eyeRest',
        '15:40 hydration+eyeRest',
        '16:00 stretch+eyeRest',
        '16:20 eyeRest',
        '16:30 hydration',
        '16:40 eyeRest',
        '17:00 stretch+eyeRest',
        '17:15 hydration+eyeRest',
        '17:40 eyeRest',
      ]);
      expect((await g.plannedPending()).where((p) => _inRange(p.fireAt, mon(14), mon(15))), isEmpty);
      expect((await g.plannedPending()).where((p) => p.fireAt.isBefore(mon(10))), isEmpty);
      await g.expectIdempotent();
    });

    test('10. day off today empties today and leaves tomorrow alone; clearing restores the plan', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);
      g.advanceTo(mon(9, 30));
      await g.reconcile(ReconcileTrigger.resume);
      final before = await g.pending();

      await g.setDayOff(g.today);
      await g.reconcile(ReconcileTrigger.configChange);

      // The 24 h horizon from 09:30 reaches Tuesday 09:20 (its first slot).
      await g.expectPending(['Tue 09:20 eyeRest']);
      final monday = (await g.plannedPending()).where((p) => p.fireAt.isBefore(tz.TZDateTime(cairo, 2026, 10, 6)));
      expect(monday, isEmpty);
      expect((await g.snapshot()).todayOverride?.kind, DayOverrideKind.off);
      expect((await g.snapshot()).onDuty, isFalse);

      await g.clearDayOverride(g.today);
      await g.reconcile(ReconcileTrigger.configChange);

      await g.expectPending([
        '09:40 hydration+eyeRest',
        '10:00 stretch+eyeRest',
        '10:20 eyeRest',
        '10:30 hydration',
        '10:40 eyeRest',
        '11:00 stretch+eyeRest',
        '11:15 hydration+eyeRest',
        '11:40 eyeRest',
        '12:00 hydration+stretch+eyeRest',
        '12:20 eyeRest',
        '12:40 hydration+eyeRest',
        '13:00 stretch+eyeRest',
        '13:20 eyeRest',
        '13:30 hydration',
        '13:40 eyeRest',
        '14:00 stretch+eyeRest',
        '14:15 hydration+eyeRest',
        '14:40 eyeRest',
        '15:00 hydration+stretch+eyeRest',
        '15:20 eyeRest',
        '15:40 hydration+eyeRest',
        '16:00 stretch+eyeRest',
        '16:20 eyeRest',
        '16:30 hydration',
        '16:40 eyeRest',
        'Tue 09:20 eyeRest',
      ]);
      expect(await g.pending(), before, reason: 'plan restored');
      await g.expectIdempotent();
    });

    test('11a. working late +60 from 16:30: slots continue to 17:59', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);
      g.advanceTo(mon(16, 30));
      await g.reconcile(ReconcileTrigger.resume);

      final o = await g.extendWorkDay(g.today, 60);
      expect(o!.extendMinutes, 60);
      await g.reconcile(ReconcileTrigger.configChange);

      await g.expectPending([
        '16:40 eyeRest',
        '17:00 stretch+eyeRest',
        '17:15 hydration+eyeRest',
        '17:40 eyeRest',
        'Tue 09:20 eyeRest',
        'Tue 09:40 hydration+eyeRest',
        'Tue 10:00 stretch+eyeRest',
        'Tue 10:20 eyeRest',
        'Tue 10:30 hydration',
        'Tue 10:40 eyeRest',
        'Tue 11:00 stretch+eyeRest',
        'Tue 11:15 hydration+eyeRest',
        'Tue 11:40 eyeRest',
        'Tue 12:00 hydration+stretch+eyeRest',
        'Tue 12:20 eyeRest',
        'Tue 12:40 hydration+eyeRest',
        'Tue 13:00 stretch+eyeRest',
        'Tue 13:20 eyeRest',
        'Tue 13:30 hydration',
        'Tue 13:40 eyeRest',
        'Tue 14:00 stretch+eyeRest',
        'Tue 14:15 hydration+eyeRest',
        'Tue 14:40 eyeRest',
        'Tue 15:00 hydration+stretch+eyeRest',
        'Tue 15:20 eyeRest',
        'Tue 15:40 hydration+eyeRest',
        'Tue 16:00 stretch+eyeRest',
        'Tue 16:20 eyeRest',
        'Tue 16:30 hydration',
      ]);
      final monday = (await g.plannedPending()).where((p) => p.fireAt.isBefore(tz.TZDateTime(cairo, 2026, 10, 6)));
      expect(monday.map((p) => p.fireAt).where((t) => !t.isBefore(mon(17))), isNotEmpty);
      expect(monday.every((p) => p.fireAt.isBefore(mon(18))), isTrue);
      await g.expectIdempotent();
    });

    test('11b. repeated extensions accumulate but cap at +240 (work window ends 21:00)', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);
      g.advanceTo(mon(16, 30));
      await g.reconcile(ReconcileTrigger.resume);

      await g.extendWorkDay(g.today, 60);
      await g.reconcile(ReconcileTrigger.configChange);
      final o = await g.extendWorkDay(g.today, 240); // 60 + 240 = 300, capped
      expect(o!.extendMinutes, kMaxExtendMinutes);
      await g.reconcile(ReconcileTrigger.configChange);

      await g.expectPending([
        '16:40 eyeRest',
        '17:00 stretch+eyeRest',
        '17:15 hydration+eyeRest',
        '17:40 eyeRest',
        '18:00 hydration+stretch+eyeRest',
        '18:20 eyeRest',
        '18:40 hydration+eyeRest',
        '19:00 stretch+eyeRest',
        '19:20 eyeRest',
        '19:30 hydration',
        '19:40 eyeRest',
        '20:00 stretch+eyeRest',
        '20:15 hydration+eyeRest',
        '20:40 eyeRest',
        'Tue 09:20 eyeRest',
        'Tue 09:40 hydration+eyeRest',
        'Tue 10:00 stretch+eyeRest',
        'Tue 10:20 eyeRest',
        'Tue 10:30 hydration',
        'Tue 10:40 eyeRest',
        'Tue 11:00 stretch+eyeRest',
        'Tue 11:15 hydration+eyeRest',
        'Tue 11:40 eyeRest',
        'Tue 12:00 hydration+stretch+eyeRest',
        'Tue 12:20 eyeRest',
        'Tue 12:40 hydration+eyeRest',
        'Tue 13:00 stretch+eyeRest',
        'Tue 13:20 eyeRest',
        'Tue 13:30 hydration',
        'Tue 13:40 eyeRest',
        'Tue 14:00 stretch+eyeRest',
        'Tue 14:15 hydration+eyeRest',
        'Tue 14:40 eyeRest',
        'Tue 15:00 hydration+stretch+eyeRest',
        'Tue 15:20 eyeRest',
        'Tue 15:40 hydration+eyeRest',
        'Tue 16:00 stretch+eyeRest',
        'Tue 16:20 eyeRest',
        'Tue 16:30 hydration',
      ]);
      final monday = (await g.plannedPending()).where((p) => p.fireAt.isBefore(tz.TZDateTime(cairo, 2026, 10, 6)));
      expect(monday.every((p) => p.fireAt.isBefore(mon(21))), isTrue);
      await g.expectIdempotent();
    });

    test('11c. working late is capped at midnight', () async {
      g = Gate.create(mon(9));
      await g.saveMonday([TimeWindow.hm(20, 0, 22, 0)]);
      await g.reconcile(ReconcileTrigger.configChange);
      g.advanceTo(mon(21));
      await g.reconcile(ReconcileTrigger.resume);

      await g.extendWorkDay(g.today, 240); // 22:00 + 4 h would be 02:00 tomorrow
      await g.reconcile(ReconcileTrigger.configChange);

      await g.expectPending([
        '21:20 eyeRest',
        '21:30 hydration',
        '21:40 eyeRest',
        '22:00 stretch+eyeRest',
        '22:15 hydration+eyeRest',
        '22:40 eyeRest',
        '23:00 hydration+stretch+eyeRest',
        '23:20 eyeRest',
        '23:40 hydration+eyeRest',
        'Tue 09:20 eyeRest',
        'Tue 09:40 hydration+eyeRest',
        'Tue 10:00 stretch+eyeRest',
        'Tue 10:20 eyeRest',
        'Tue 10:30 hydration',
        'Tue 10:40 eyeRest',
        'Tue 11:00 stretch+eyeRest',
        'Tue 11:15 hydration+eyeRest',
        'Tue 11:40 eyeRest',
        'Tue 12:00 hydration+stretch+eyeRest',
        'Tue 12:20 eyeRest',
        'Tue 12:40 hydration+eyeRest',
        'Tue 13:00 stretch+eyeRest',
        'Tue 13:20 eyeRest',
        'Tue 13:30 hydration',
        'Tue 13:40 eyeRest',
        'Tue 14:00 stretch+eyeRest',
        'Tue 14:15 hydration+eyeRest',
        'Tue 14:40 eyeRest',
        'Tue 15:00 hydration+stretch+eyeRest',
        'Tue 15:20 eyeRest',
        'Tue 15:40 hydration+eyeRest',
        'Tue 16:00 stretch+eyeRest',
        'Tue 16:20 eyeRest',
        'Tue 16:30 hydration',
        'Tue 16:40 eyeRest',
      ]);
      final late = (await g.plannedPending()).where(
        (p) =>
            !p.fireAt.isBefore(tz.TZDateTime(cairo, 2026, 10, 6)) &&
            p.fireAt.isBefore(tz.TZDateTime(cairo, 2026, 10, 6, 9)),
      );
      expect(late, isEmpty, reason: 'nothing between midnight and tomorrow 09:00');
      await g.expectIdempotent();
    });

    test('12. Done on the recovery reminder completes every type and reschedules from the completion', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);
      g.advanceTo(mon(10, 5));
      await g.startShield(ShieldPreset.min25);
      await g.reconcile(ReconcileTrigger.configChange);
      g.advanceTo(mon(10, 31));
      final recovery = g.os.delivered.last;
      expect(recovery.recovery, isTrue);
      expect(recovery.types, {RoutineType.hydration, RoutineType.eyeRest});

      g.advanceTo(mon(10, 32));
      await g.handle(
        ReminderAction(
          kind: ReminderActionKind.done,
          types: recovery.types,
          scheduledAt: recovery.fireAt,
          notificationId: recovery.notificationId,
        ),
      );

      final events = await g.todaysEvents();
      expect(events.map((e) => (e.type, e.outcome)), [
        (RoutineType.hydration, ReminderOutcome.done),
        (RoutineType.eyeRest, ReminderOutcome.done),
      ]);
      expect(events.first.waterMl, 250);
      // Hydration 10:32 + 45 min, eye rest every 20 min from 10:32; stretch was
      // not part of the recovery, so it keeps its 11:00 slot.
      await g.expectPending([
        '10:52 eyeRest',
        '11:00 stretch',
        '11:12 hydration+eyeRest',
        '11:32 eyeRest',
        '11:52 eyeRest',
        '12:00 hydration+stretch',
        '12:12 eyeRest',
        '12:32 eyeRest',
        '12:47 hydration+eyeRest',
        '13:00 stretch',
        '13:12 eyeRest',
        '13:32 hydration+eyeRest',
        '13:52 eyeRest',
        '14:00 stretch',
        '14:12 hydration+eyeRest',
        '14:32 eyeRest',
        '14:52 eyeRest',
        '15:00 hydration+stretch',
        '15:12 eyeRest',
        '15:32 eyeRest',
        '15:47 hydration+eyeRest',
        '16:00 stretch',
        '16:12 eyeRest',
        '16:32 hydration+eyeRest',
        '16:52 eyeRest',
        'Tue 09:20 eyeRest',
        'Tue 09:40 hydration+eyeRest',
        'Tue 10:00 stretch+eyeRest',
        'Tue 10:20 eyeRest',
        'Tue 10:30 hydration',
      ]);
      expect(g.os.shieldStatusShown, isFalse);
      await g.expectIdempotent();
    });

    test('13. snooze into a Shield lands in the recovery reminder', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);
      g.advanceTo(mon(9, 46));
      final reminder = g.os.delivered.last; // 09:40 hydration + eye rest
      expect(describePlanned(reminder), '09:40 hydration+eyeRest');

      await g.startShield(ShieldPreset.min25); // 09:46-10:11
      await g.reconcile(ReconcileTrigger.configChange);
      await g.expectPending([
        '10:11 stretch+eyeRest (recovery)',
        '10:20 eyeRest',
        '10:30 hydration',
        '10:40 eyeRest',
        '11:00 stretch+eyeRest',
        '11:15 hydration+eyeRest',
        '11:40 eyeRest',
        '12:00 hydration+stretch+eyeRest',
        '12:20 eyeRest',
        '12:40 hydration+eyeRest',
        '13:00 stretch+eyeRest',
        '13:20 eyeRest',
        '13:30 hydration',
        '13:40 eyeRest',
        '14:00 stretch+eyeRest',
        '14:15 hydration+eyeRest',
        '14:40 eyeRest',
        '15:00 hydration+stretch+eyeRest',
        '15:20 eyeRest',
        '15:40 hydration+eyeRest',
        '16:00 stretch+eyeRest',
        '16:20 eyeRest',
        '16:30 hydration',
        '16:40 eyeRest',
        'Tue 09:20 eyeRest',
        'Tue 09:40 hydration+eyeRest',
      ]);
      expect((await g.recoveries()).single.types, {
        RoutineType.stretch,
        RoutineType.eyeRest,
      }, reason: 'before the snooze hydration has no slot inside the Shield');

      g.advanceTo(mon(9, 47));
      await g.handle(
        ReminderAction(
          kind: ReminderActionKind.snooze,
          types: reminder.types,
          scheduledAt: reminder.fireAt,
          notificationId: reminder.notificationId,
        ),
      ); // snoozed until 09:57, inside the Shield

      await g.expectPending([
        '10:11 hydration+stretch+eyeRest (recovery)',
        '10:17 eyeRest',
        '10:37 hydration+eyeRest',
        '10:57 stretch+eyeRest',
        '11:17 eyeRest',
        '11:27 hydration',
        '11:37 eyeRest',
        '11:57 stretch+eyeRest',
        '12:12 hydration+eyeRest',
        '12:37 eyeRest',
        '12:57 hydration+stretch+eyeRest',
        '13:17 eyeRest',
        '13:37 hydration+eyeRest',
        '13:57 stretch+eyeRest',
        '14:17 eyeRest',
        '14:27 hydration',
        '14:37 eyeRest',
        '14:57 stretch+eyeRest',
        '15:12 hydration+eyeRest',
        '15:37 eyeRest',
        '15:57 hydration+stretch+eyeRest',
        '16:17 eyeRest',
        '16:37 hydration+eyeRest',
        '16:57 eyeRest',
        'Tue 09:20 eyeRest',
        'Tue 09:40 hydration+eyeRest',
      ]);
      expect((await g.plannedPending()).where((p) => _inRange(p.fireAt, mon(9, 47), mon(10, 11))), isEmpty);
      final recovery = (await g.recoveries()).single;
      expect(recovery.fireAt.isAtSameMomentAs(mon(10, 11)), isTrue);
      expect(recovery.types, RoutineType.values.toSet());
      await g.expectIdempotent();
    });

    test(
      '14. diagnostics notification (id 1) survives diff reconciles, full replaces clear it; status id 2 is untouched',
      () async {
        g = Gate.create(mon(9));
        await g.reconcile(ReconcileTrigger.launch);
        await g.os.scheduleTest(at: mon(9, 30));
        expect(await g.os.pendingIds(), contains(kTestNotificationId));

        // Plans change under every diff trigger; the diagnostics id is never cancelled.
        g.advanceTo(mon(9, 10));
        await g.startShield(ShieldPreset.min50);
        for (final t in [
          ReconcileTrigger.resume,
          ReconcileTrigger.launch,
          ReconcileTrigger.action,
          ReconcileTrigger.periodic,
          ReconcileTrigger.manual,
        ]) {
          final run = await g.reconcile(t);
          expect(await g.os.pendingIds(), contains(kTestNotificationId), reason: '${t.name} must keep id 1');
          if (t == ReconcileTrigger.resume) expect(run.cancelled, greaterThan(0));
        }
        await g.endShield();
        await g.reconcile(ReconcileTrigger.resume);
        expect(await g.os.pendingIds(), contains(kTestNotificationId));
        expect(g.os.cancelledIds.where((id) => id < kReservedNotificationIdLimit), isEmpty);
        expect(g.os.cancelAllCalls, 0);
        expect(g.os.shieldStatusShown, isFalse, reason: 'cleared via clearShieldStatus, not via the diff');

        // Status id 2 is driven by the reconcile outside the diff: shown while active,
        // and a diff reconcile does not disturb it.
        await g.startShield(ShieldPreset.min25);
        await g.reconcile(ReconcileTrigger.configChange);
        expect(g.os.shieldStatusShown, isTrue);
        await g.reconcile(ReconcileTrigger.resume);
        expect(g.os.shieldStatusShown, isTrue);
        expect(g.os.cancelledIds, isNot(contains(kShieldStatusNotificationId)));

        // Every full-replace trigger clears the diagnostics notification.
        for (final t in [ReconcileTrigger.configChange, ReconcileTrigger.timezoneChange, ReconcileTrigger.boot]) {
          await g.os.scheduleTest(at: mon(9, 30));
          await g.reconcile(t);
          expect(await g.os.pendingIds(), isNot(contains(kTestNotificationId)), reason: '${t.name} is a full replace');
          expect(g.os.shieldStatusShown, isTrue, reason: 'cancelAll never removes the shown status');
        }
        await g.expectIdempotent();
      },
    );

    test('16. launch at 08:55 before the shift: the whole workday, inside work hours, under the 50 cap', () async {
      g = Gate.create(mon(8, 55));
      await g.reconcile(ReconcileTrigger.launch);

      await g.expectPending(_mondayPlan);
      final all = await g.plannedPending();
      expect(all.length, lessThanOrEqualTo(50));
      for (final p in all) {
        expect(p.fireAt.isBefore(mon(9)), isFalse, reason: '${describe(p.fireAt, p.types)} is before 09:00');
        expect(p.fireAt.isAfter(mon(17)), isFalse, reason: '${describe(p.fireAt, p.types)} is after 17:00');
      }
      await g.expectIdempotent();
    });

    test('17. End Shield from the notification action behaves like ending in the app', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);
      g.advanceTo(mon(10, 5));
      await g.startShield(ShieldPreset.min25);
      await g.reconcile(ReconcileTrigger.configChange);
      expect(g.os.shieldStatusShown, isTrue);

      g.advanceTo(mon(10, 25));
      // The background handler reconciles by itself; no sync service involved.
      await g.handle(
        ReminderAction(
          kind: ReminderActionKind.endShield,
          types: const {},
          scheduledAt: mon(10, 25),
          notificationId: kShieldStatusNotificationId,
        ),
      );

      expect(g.os.shieldStatusShown, isFalse);
      final recovery = (await g.recoveries()).single;
      expect(recovery.fireAt.isAtSameMomentAs(mon(10, 26)), isTrue, reason: 'early end -> recovery one minute later');
      // Eye rest was held back; hydration's 10:30 slot merges into the recovery.
      expect(recovery.types, {RoutineType.eyeRest, RoutineType.hydration});
      expect((await g.plannedPending()).where((p) => p.fireAt.isBefore(mon(10, 26))), isEmpty);
      // Regular slots after the Shield are back.
      expect(await g.pending(), containsAll(['10:40 eyeRest', '11:00 stretch+eyeRest']));
      await g.expectIdempotent();
    });

    test('18. "until I turn it off" does not leak into the next morning', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);
      g.advanceTo(mon(15));
      await g.reconcile(ReconcileTrigger.resume);
      await g.startShield(ShieldPreset.untilOff);
      await g.reconcile(ReconcileTrigger.configChange);
      expect(g.os.shieldStatusUntil!.isAtSameMomentAs(mon(17)), isTrue);

      // Next morning, app opened at 08:55.
      g.advanceTo(tz.TZDateTime(cairo, 2026, 10, 6, 8, 55));
      await g.reconcile(ReconcileTrigger.launch);

      expect(g.os.shieldStatusShown, isFalse, reason: 'the Shield expired yesterday at 17:00');
      expect(await g.recoveries(), isEmpty);
      final plan = await g.pending();
      expect(plan.take(6), [
        'Tue 09:20 eyeRest',
        'Tue 09:40 hydration+eyeRest',
        'Tue 10:00 stretch+eyeRest',
        'Tue 10:20 eyeRest',
        'Tue 10:30 hydration',
        'Tue 10:40 eyeRest',
      ]);
      expect(plan, hasLength(26));
      await g.expectIdempotent();
    });

    // BUG (reported, production logic untouched): the planner merges slots within
    // 5 minutes into one notification, but the absorbed slot is not remembered
    // once the merged notification has been delivered without an action (no event
    // row exists until Done/Snooze). The next reconcile (periodic/resume) then
    // re-plans the absorbed slot on its own: after '09:40 hydration+eyeRest' fires,
    // '09:45 hydration' reappears and fires 5 minutes later (same at 12:40/12:45
    // and 14:15 -> 14:20), i.e. a duplicate nudge per merged group.
    test('19a. delivery loop: delivered list equals the day plan (one nudge per merged group)', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);
      final shieldStart = mon(11, 1);
      final shieldEnd = mon(11, 26);
      var shielded = false;

      for (var i = 0; i < 100; i++) {
        final next = (await g.plannedPending()).where((p) => p.fireAt.isBefore(tz.TZDateTime(cairo, 2026, 10, 6)));
        if (next.isEmpty) break;
        var target = next.first.fireAt;
        if (!shielded && !target.isBefore(shieldStart)) {
          // The user starts a 25 min Shield at 11:01, between two reminders.
          g.advanceTo(shieldStart);
          await g.startShield(ShieldPreset.min25);
          await g.reconcile(ReconcileTrigger.configChange);
          shielded = true;
          continue;
        }
        target = tz.TZDateTime.from(target, cairo);
        final fired = g.os.fireDue(target);
        g.clock.current = target;
        expect(fired, isNotEmpty);
        await g.reconcile(ReconcileTrigger.periodic);
      }

      final delivered = g.os.delivered.map(describePlanned).toList();
      // Baseline minus the 11:15 slot that fell inside the Shield, plus the recovery.
      final expected = [..._mondayPlan]..remove('11:15 hydration+eyeRest');
      expected.insert(expected.indexOf('11:40 eyeRest'), '11:26 hydration+eyeRest (recovery)');
      expect(delivered, expected);
      for (final r in g.os.delivered) {
        expect(r.fireAt.isBefore(mon(9)), isFalse);
        expect(r.fireAt.isAfter(mon(17)), isFalse);
        expect(_inRange(r.fireAt, shieldStart, shieldEnd), isFalse, reason: 'delivered inside the Shield');
      }
      expect(g.os.delivered.where((r) => r.recovery), hasLength(1));
      await g.expectIdempotent();
    });

    test('19b. delivery loop: every delivered reminder is inside work hours and outside the Shield', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);
      final shieldStart = mon(11, 1);
      final shieldEnd = mon(11, 26);
      var shielded = false;

      for (var i = 0; i < 100; i++) {
        final next = (await g.plannedPending()).where((p) => p.fireAt.isBefore(tz.TZDateTime(cairo, 2026, 10, 6)));
        if (next.isEmpty) break;
        final target = tz.TZDateTime.from(next.first.fireAt, cairo);
        if (!shielded && !target.isBefore(shieldStart)) {
          // The user starts a 25 min Shield at 11:01, between two reminders.
          g.advanceTo(shieldStart);
          await g.startShield(ShieldPreset.min25);
          await g.reconcile(ReconcileTrigger.configChange);
          shielded = true;
          continue;
        }
        g.clock.current = target;
        expect(g.os.fireDue(target), isNotEmpty);
        await g.reconcile(ReconcileTrigger.periodic);
      }

      expect(g.os.delivered, isNotEmpty);
      for (final r in g.os.delivered) {
        expect(r.fireAt.isBefore(mon(9)), isFalse, reason: describePlanned(r));
        expect(r.fireAt.isAfter(mon(17)), isFalse, reason: describePlanned(r));
        expect(_inRange(r.fireAt, shieldStart, shieldEnd), isFalse, reason: 'delivered inside the Shield');
      }
      // Exactly one recovery, at 11:26 (Shield 11:01-11:26, nothing delivered in between).
      final recoveries = g.os.delivered.where((r) => r.recovery).toList();
      expect(recoveries.map(describePlanned), ['11:26 hydration+eyeRest (recovery)']);
      // Per routine: each hydration/stretch/eye-rest slot of the baseline is delivered at least once.
      for (final t in RoutineType.values) {
        final planned = _mondayPlan.where((e) => e.contains(t.name)).length;
        final got = g.os.delivered.where((r) => r.types.contains(t)).length;
        expect(got, greaterThanOrEqualTo(planned - 1), reason: '${t.name}: planned $planned, delivered $got');
      }
      await g.expectIdempotent();
    });

    test('15. idempotency after a mix of actions: the second resume reconcile adds 0 and cancels 0', () async {
      g = Gate.create(mon(9));
      await g.reconcile(ReconcileTrigger.launch);
      g.advanceTo(mon(10, 5));
      await g.startShield(ShieldPreset.min25);
      await g.reconcile(ReconcileTrigger.configChange);
      g.advanceTo(mon(10, 12));
      await g.extendShield(const Duration(minutes: 20));
      await g.reconcile(ReconcileTrigger.configChange);
      g.advanceTo(mon(10, 40));
      await g.endShield();
      await g.reconcile(ReconcileTrigger.configChange);
      g.advanceTo(mon(10, 50));
      await g.handle(
        ReminderAction(
          kind: ReminderActionKind.done,
          types: const {RoutineType.stretch},
          scheduledAt: mon(10),
          notificationId: 1234,
        ),
      );
      await g.extendWorkDay(g.today, 30);
      await g.reconcile(ReconcileTrigger.configChange);
      g.advanceTo(mon(12, 30));

      await g.reconcile(ReconcileTrigger.resume);
      final second = await g.reconcile(ReconcileTrigger.resume);
      expect(second.added, 0);
      expect(second.cancelled, 0);
      // And a full replace followed by a resume is also a fixed point.
      await g.reconcile(ReconcileTrigger.configChange);
      final afterReplace = await g.reconcile(ReconcileTrigger.resume);
      expect(afterReplace.added, 0);
      expect(afterReplace.cancelled, 0);
    });
  });
}
