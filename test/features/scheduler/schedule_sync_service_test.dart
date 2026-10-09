// Futures from fake-async-driven calls are driven by the test, not awaited.
// ignore_for_file: discarded_futures
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/scheduler/presentation/schedule_sync_service.dart';
import 'package:knight_rise/features/settings/domain/entities/app_settings.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/fakes.dart';
import '../../helpers/tz.dart';

const Duration _debounce = Duration(milliseconds: 500);
const ReconcileTrigger _config = ReconcileTrigger.configChange;

void main() {
  late FakeRoutineRepository routines;
  late FakeWorkScheduleRepository work;
  late FakeSettingsRepository settings;
  late FakeReminderEventRepository events;
  late FakeShieldRepository shields;
  late FakeDayOverrideRepository overrides;
  late FakeScheduleReconciler reconciler;
  late FakeDeviceTimezone deviceTz;
  late FakeReconcileRunRepository runsRepo;
  late FixedClock clock;
  late ScheduleSyncService service;

  setUp(() {
    tz.setLocalLocation(cairo);
    getIt.registerSingleton<tz.Location>(cairo);
    routines = FakeRoutineRepository();
    work = FakeWorkScheduleRepository();
    settings = FakeSettingsRepository();
    events = FakeReminderEventRepository();
    shields = FakeShieldRepository();
    overrides = FakeDayOverrideRepository();
    reconciler = FakeScheduleReconciler();
    deviceTz = FakeDeviceTimezone('Africa/Cairo');
    runsRepo = FakeReconcileRunRepository();
    clock = FixedClock(at(cairo, 2026, 10, 5, 12));
  });

  tearDown(() async {
    await getIt.reset();
    tz.setLocalLocation(tz.UTC);
  });

  ScheduleSyncService build() => service = ScheduleSyncService(
    routines,
    work,
    settings,
    events,
    shields,
    overrides,
    reconciler,
    clock,
    deviceTz,
    runsRepo,
  );

  void run(void Function(FakeAsync async) body) {
    fakeAsync((async) {
      build();
      body(async);
      service.dispose();
      async.flushMicrotasks();
    });
  }

  ReminderEvent event() =>
      ReminderEvent(type: RoutineType.hydration, outcome: ReminderOutcome.done, at: clock.now(), waterMl: 250);

  test('start reconciles once for launch; initial emissions are ignored', () {
    run((async) {
      service.start();
      async.elapse(const Duration(seconds: 5));
      expect(reconciler.calls, [ReconcileTrigger.launch]);
    });
  });

  test('routine change -> one configChange after 500 ms', () {
    run((async) {
      service.start();
      async.flushMicrotasks();
      routines.save(Routine.defaults.first.copyWith(intervalMinutes: 30));
      async.elapse(_debounce - const Duration(milliseconds: 1));
      expect(reconciler.calls, [ReconcileTrigger.launch]);
      async.elapse(const Duration(milliseconds: 1));
      expect(reconciler.calls, [ReconcileTrigger.launch, _config]);
    });
  });

  test('work schedule change -> configChange', () {
    run((async) {
      service.start();
      async.flushMicrotasks();
      work.save(work.current);
      async.elapse(_debounce);
      expect(reconciler.calls.last, _config);
    });
  });

  test('burst of 5 changes coalesces into one call', () {
    run((async) {
      service.start();
      async.flushMicrotasks();
      for (var i = 0; i < 5; i++) {
        routines.save(Routine.defaults.first.copyWith(intervalMinutes: 20 + i));
        async.elapse(const Duration(milliseconds: 100));
      }
      async.elapse(_debounce);
      expect(reconciler.calls, [ReconcileTrigger.launch, _config]);
    });
  });

  test('burst mixing action and configChange prefers configChange', () {
    run((async) {
      service.start();
      async.flushMicrotasks();
      routines.save(Routine.defaults.first.copyWith(intervalMinutes: 25));
      async.elapse(const Duration(milliseconds: 50));
      events.add(event());
      async.elapse(_debounce);
      expect(reconciler.calls, [ReconcileTrigger.launch, _config]);
    });
  });

  test('theme and timezoneId changes do not reconcile; precisionTiming does', () {
    run((async) {
      service.start();
      async.flushMicrotasks();
      settings.save(const AppSettings().copyWith(themeVariant: ThemeVariant.amoled));
      async.elapse(_debounce * 2);
      settings.save(const AppSettings().copyWith(themeVariant: ThemeVariant.amoled, timezoneId: 'Europe/Paris'));
      async.elapse(_debounce * 2);
      expect(reconciler.calls, [ReconcileTrigger.launch]);

      settings.save(const AppSettings().copyWith(precisionTiming: true));
      async.elapse(_debounce);
      expect(reconciler.calls, [ReconcileTrigger.launch, _config]);
    });
  });

  test('shieldRecoverOnExit toggle reconciles as a configChange', () {
    run((async) {
      service.start();
      async.flushMicrotasks();
      settings.save(const AppSettings().copyWith(shieldRecoverOnExit: false));
      async.elapse(_debounce);
      expect(reconciler.calls, [ReconcileTrigger.launch, _config]);
    });
  });

  ShieldSession shield() => ShieldSession(
    startAt: clock.now(),
    endAt: clock.now().add(const Duration(minutes: 25)),
    reason: ShieldReason.focus,
  );

  test('Shield start, extend and end -> one configChange each after the debounce', () {
    run((async) {
      service.start();
      async.flushMicrotasks();
      shields.add(shield());
      async.elapse(_debounce - const Duration(milliseconds: 1));
      expect(reconciler.calls, [ReconcileTrigger.launch]);
      async.elapse(const Duration(milliseconds: 1));
      expect(reconciler.calls, [ReconcileTrigger.launch, _config]);

      shields.update(shields.all.single.copyWith(endAt: clock.now().add(const Duration(minutes: 40))));
      async.elapse(_debounce);
      shields.update(shields.all.single.copyWith(endedAt: clock.now()));
      async.elapse(_debounce);
      expect(reconciler.calls, [ReconcileTrigger.launch, _config, _config, _config]);
    });
  });

  test('day override set / clear -> configChange', () {
    run((async) {
      service.start();
      async.flushMicrotasks();
      final today = DateTime.utc(2026, 10, 5);
      overrides.set(DayOverride(date: today, kind: DayOverrideKind.off));
      async.elapse(_debounce);
      expect(reconciler.calls, [ReconcileTrigger.launch, _config]);
      overrides.clear(today);
      async.elapse(_debounce);
      expect(reconciler.calls, [ReconcileTrigger.launch, _config, _config]);
    });
  });

  test('burst of Shield + override edits coalesces into one configChange', () {
    run((async) {
      service.start();
      async.flushMicrotasks();
      shields.add(shield());
      async.elapse(const Duration(milliseconds: 100));
      overrides.set(DayOverride(date: DateTime.utc(2026, 10, 5), kind: DayOverrideKind.extend, extendMinutes: 60));
      async.elapse(_debounce);
      expect(reconciler.calls, [ReconcileTrigger.launch, _config]);
    });
  });

  test('after midnight, onResume re-subscribes Shield and override watches for the new day', () {
    run((async) {
      service.start();
      async.flushMicrotasks();
      clock.advance(const Duration(days: 1));
      service.onResume();
      async.flushMicrotasks();
      final before = reconciler.calls.length;
      shields.add(shield());
      async.elapse(_debounce);
      expect(reconciler.calls.length, before + 1);
      expect(reconciler.calls.last, _config);
    });
  });

  test('reconcileNow is a no-op before start, runs the trigger once started', () {
    run((async) {
      service.reconcileNow(ReconcileTrigger.periodic);
      async.flushMicrotasks();
      expect(reconciler.calls, isEmpty);
      service.start();
      async.flushMicrotasks();
      service.reconcileNow(ReconcileTrigger.periodic);
      async.flushMicrotasks();
      expect(reconciler.calls, [ReconcileTrigger.launch, ReconcileTrigger.periodic]);
    });
  });

  test('reconcileNow is serialized with other runs and a no-op after dispose', () {
    reconciler.delay = const Duration(seconds: 1);
    run((async) {
      service.start();
      async.flushMicrotasks();
      service.reconcileNow(ReconcileTrigger.periodic);
      async.elapse(const Duration(seconds: 5));
      expect(reconciler.maxConcurrent, 1);
      expect(reconciler.calls, [ReconcileTrigger.launch, ReconcileTrigger.periodic]);
      service
        ..dispose()
        ..reconcileNow(ReconcileTrigger.periodic);
      async.elapse(const Duration(seconds: 5));
      expect(reconciler.calls, hasLength(2));
    });
  });

  test('event added -> action', () {
    run((async) {
      service.start();
      async.flushMicrotasks();
      events.add(event());
      async.elapse(_debounce);
      expect(reconciler.calls, [ReconcileTrigger.launch, ReconcileTrigger.action]);
    });
  });

  test('never runs concurrently; changes during a run cause exactly one rerun', () {
    reconciler = FakeScheduleReconciler(delay: const Duration(seconds: 2));
    run((async) {
      service.start();
      async.elapse(const Duration(milliseconds: 100)); // launch running
      routines.save(Routine.defaults.first.copyWith(intervalMinutes: 31));
      async.elapse(_debounce); // fires while launch still running -> queued
      routines.save(Routine.defaults.first.copyWith(intervalMinutes: 32));
      async.elapse(_debounce);
      expect(reconciler.calls, [ReconcileTrigger.launch]);
      async.elapse(const Duration(seconds: 10));
      expect(reconciler.calls, [ReconcileTrigger.launch, _config]);
      expect(reconciler.maxConcurrent, 1);
    });
  });

  test('reconciler errors are swallowed and later runs still happen', () {
    reconciler.throwOnNext = StateError('boom');
    run((async) {
      service.start();
      async.flushMicrotasks();
      routines.save(Routine.defaults.first.copyWith(intervalMinutes: 40));
      async.elapse(_debounce);
      expect(reconciler.calls, [ReconcileTrigger.launch, _config]);
    });
  });

  test('start persists the device timezone on first launch before reconciling, without emitting', () {
    run((async) {
      var emitted = 0;
      service.timezoneChanged.listen((_) => emitted++);
      expect(settings.current.timezoneId, isNull);
      service.start();
      async.flushMicrotasks();
      expect(settings.current.timezoneId, 'Africa/Cairo');
      expect(reconciler.calls, [ReconcileTrigger.launch]);
      expect(emitted, 0);
    });
  });

  test('start keeps an already stored timezone id', () {
    run((async) {
      settings.save(const AppSettings().copyWith(timezoneId: 'Europe/Paris'));
      service.start();
      async.flushMicrotasks();
      expect(settings.current.timezoneId, 'Europe/Paris');
    });
  });

  test('start leaves timezone unset when the device lookup fails', () {
    run((async) {
      deviceTz.id = null;
      service.start();
      async.flushMicrotasks();
      expect(settings.current.timezoneId, isNull);
      expect(reconciler.calls, [ReconcileTrigger.launch]);
    });
  });

  test('onResume with same timezone -> resume, id persisted when it was null', () {
    run((async) {
      service.start();
      async.flushMicrotasks();
      service.onResume();
      async.flushMicrotasks();
      expect(reconciler.calls, [ReconcileTrigger.launch, ReconcileTrigger.resume]);
      expect(settings.current.timezoneId, 'Africa/Cairo');
      service.onResume();
      async.flushMicrotasks();
      expect(reconciler.calls.last, ReconcileTrigger.resume);
    });
  });

  test('onResume with changed timezone -> timezoneChange, persists, swaps location, emits', () {
    run((async) {
      settings.save(const AppSettings().copyWith(timezoneId: 'Africa/Cairo'));
      service.start();
      async.flushMicrotasks();
      var emitted = 0;
      service.timezoneChanged.listen((_) => emitted++);
      deviceTz.id = 'America/New_York';
      service.onResume();
      async.flushMicrotasks();
      expect(reconciler.calls.last, ReconcileTrigger.timezoneChange);
      expect(settings.current.timezoneId, 'America/New_York');
      expect(tz.local.name, 'America/New_York');
      expect(getIt<tz.Location>().name, 'America/New_York');
      expect(emitted, 1);
    });
  });

  test('onResume after midnight resubscribes events for the new day', () {
    run((async) {
      service.start();
      async.flushMicrotasks();
      clock.advance(const Duration(days: 1));
      service.onResume();
      async.flushMicrotasks();
      final before = reconciler.calls.length;
      events.add(event());
      async.elapse(_debounce);
      expect(reconciler.calls.length, before + 1);
      expect(reconciler.calls.last, ReconcileTrigger.action);
    });
  });

  test('dispose cancels pending work', () {
    fakeAsync((async) {
      build().start();
      async.flushMicrotasks();
      routines.save(Routine.defaults.first.copyWith(intervalMinutes: 50));
      async.flushMicrotasks();
      service.dispose();
      async.elapse(_debounce * 2);
      expect(reconciler.calls, [ReconcileTrigger.launch]);
    });
  });

  group('remindersWerePaused', () {
    ReconcileRun runAgo(Duration ago) => ReconcileRun(
      at: clock.now().subtract(ago),
      trigger: ReconcileTrigger.periodic,
      planned: 5,
      added: 1,
      cancelled: 0,
    );
    ReconcileRun previousRun() => runAgo(const Duration(hours: 2));

    void useRun({required int planned, required int added, String? error}) {
      reconciler = _ScriptedReconciler(planned: planned, added: added, error: error);
    }

    test('the first run ever does not emit', () {
      useRun(planned: 5, added: 5);
      run((async) {
        var emits = 0;
        service.remindersWerePaused.listen((_) => emits++);
        service.start();
        async.elapse(const Duration(seconds: 5));
        expect(reconciler.calls, [ReconcileTrigger.launch]);
        expect(emits, 0);
        expect(service.remindersPausedAt, isNull);
      });
    });

    test('a normal resume with reminders still pending does not emit', () {
      useRun(planned: 5, added: 1);
      runsRepo.runs.add(previousRun());
      run((async) {
        var emits = 0;
        service.remindersWerePaused.listen((_) => emits++);
        service.start();
        async.elapse(const Duration(seconds: 5));
        service.onResume();
        async.elapse(const Duration(seconds: 5));
        expect(emits, 0);
      });
    });

    test('re-adding the whole plan after an earlier run emits on launch and on resume', () {
      useRun(planned: 5, added: 5);
      runsRepo.runs.add(previousRun());
      run((async) {
        var emits = 0;
        service.remindersWerePaused.listen((_) => emits++);
        service.start();
        async.elapse(const Duration(seconds: 5));
        expect(emits, 1);
        expect(service.remindersPausedAt, clock.now());
        service.onResume();
        async.elapse(const Duration(seconds: 5));
        expect(emits, 2);
      });
    });

    test('a full re-add after a run older than the planning horizon does not emit', () {
      useRun(planned: 5, added: 5);
      runsRepo.runs.add(runAgo(const Duration(days: 2)));
      run((async) {
        var emits = 0;
        service.remindersWerePaused.listen((_) => emits++);
        service.start();
        async.elapse(const Duration(seconds: 5));
        service.onResume();
        async.elapse(const Duration(seconds: 5));
        expect(reconciler.calls, [ReconcileTrigger.launch, ReconcileTrigger.resume]);
        expect(emits, 0);
        expect(service.remindersPausedAt, isNull);
      });
    });

    test('a full re-add after a run 2 hours ago emits', () {
      useRun(planned: 5, added: 5);
      runsRepo.runs.add(runAgo(const Duration(hours: 2)));
      run((async) {
        var emits = 0;
        service.remindersWerePaused.listen((_) => emits++);
        service.start();
        async.elapse(const Duration(seconds: 5));
        expect(emits, 1);
      });
    });

    test('nothing planned, a failed run, and other triggers do not emit', () {
      runsRepo.runs.add(previousRun());
      for (final (planned, added, error) in [(0, 0, null), (5, 5, 'boom')]) {
        useRun(planned: planned, added: added, error: error);
        run((async) {
          var emits = 0;
          service.remindersWerePaused.listen((_) => emits++);
          service.start();
          async.elapse(const Duration(seconds: 5));
          expect(emits, 0);
        });
      }
      useRun(planned: 5, added: 5);
      run((async) {
        var emits = 0;
        service.remindersWerePaused.listen((_) => emits++);
        service.start();
        async.elapse(const Duration(seconds: 5));
        final afterLaunch = emits;
        routines.save(Routine.defaults.first.copyWith(intervalMinutes: 30));
        async.elapse(_debounce);
        expect(reconciler.calls.last, _config);
        expect(emits, afterLaunch);
      });
    });
  });
}

/// Returns a run with the given counts for every reconcile.
class _ScriptedReconciler extends FakeScheduleReconciler {
  _ScriptedReconciler({required this.planned, required this.added, this.error});

  final int planned;
  final int added;
  final String? error;

  @override
  Future<ReconcileRun> reconcile(ReconcileTrigger trigger) async {
    await super.reconcile(trigger);
    return ReconcileRun(
      at: DateTime(2026),
      trigger: trigger,
      planned: planned,
      added: added,
      cancelled: 0,
      error: error,
    );
  }
}
