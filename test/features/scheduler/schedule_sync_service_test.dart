// fake_async is a transitive dependency of flutter_test; avoids a pubspec change.
// ignore_for_file: depend_on_referenced_packages, discarded_futures
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
  late FakeScheduleReconciler reconciler;
  late FakeDeviceTimezone deviceTz;
  late FixedClock clock;
  late ScheduleSyncService service;

  setUp(() {
    tz.setLocalLocation(cairo);
    getIt.registerSingleton<tz.Location>(cairo);
    routines = FakeRoutineRepository();
    work = FakeWorkScheduleRepository();
    settings = FakeSettingsRepository();
    events = FakeReminderEventRepository();
    reconciler = FakeScheduleReconciler();
    deviceTz = FakeDeviceTimezone('Africa/Cairo');
    clock = FixedClock(at(cairo, 2026, 10, 5, 12));
  });

  tearDown(() async {
    await getIt.reset();
    tz.setLocalLocation(tz.UTC);
  });

  ScheduleSyncService build() =>
      service = ScheduleSyncService(routines, work, settings, events, reconciler, clock, deviceTz);

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
}
