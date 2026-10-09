import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/time/location_provider.dart';
import 'package:knight_rise/features/quest_log/domain/usecases/history_usecases.dart';
import 'package:knight_rise/features/scheduler/desktop/desktop_alarm_clock.dart';
import 'package:knight_rise/features/scheduler/desktop/desktop_heartbeat.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/presentation/schedule_sync_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../helpers/tz.dart';

class _MockAlarm extends Mock implements DesktopAlarmClock;

class _MockSync extends Mock implements ScheduleSyncService;

class _MockMaintain extends Mock implements MaintainHistory;

class _FixedLocation implements LocationProvider {
  @override
  tz.Location get current => cairo;
}

void main() {
  late FixedClock clock;
  late _MockAlarm alarm;
  late _MockSync sync;
  late _MockMaintain maintain;
  late DesktopHeartbeat heartbeat;

  setUpAll(() => registerFallbackValue(ReconcileTrigger.periodic));

  setUp(() {
    clock = FixedClock(at(cairo, 2026, 10, 9, 10, 0, 1));
    alarm = _MockAlarm();
    sync = _MockSync();
    maintain = _MockMaintain();
    when(() => alarm.tick()).thenAnswer((_) async {});
    when(() => sync.onResume()).thenAnswer((_) async {});
    when(() => sync.reconcileNow(any())).thenAnswer((_) async {});
    when(() => maintain()).thenAnswer((_) async {});
    heartbeat = DesktopHeartbeat(clock, alarm, sync, maintain, _FixedLocation())..start();
  });

  tearDown(() => heartbeat.dispose());

  void verifyNothingExtra() {
    verifyNever(() => sync.onResume());
    verifyNever(() => sync.reconcileNow(any()));
    verifyNever(() => maintain());
  }

  test('first beat only ticks the alarm', () async {
    await heartbeat.beat();
    verify(() => alarm.tick()).called(1);
    verifyNothingExtra();
  });

  test('normal 60 s beats do nothing extra', () async {
    for (var i = 0; i < 5; i++) {
      await heartbeat.beat();
      clock.advance(DesktopHeartbeat.period);
    }
    verify(() => alarm.tick()).called(5);
    verifyNothingExtra();
  });

  test('a gap over two minutes is a wake: onResume then maintain', () async {
    await heartbeat.beat();
    clock.advance(const Duration(minutes: 3));
    await heartbeat.beat();
    verifyInOrder([() => alarm.tick(), () => alarm.tick(), () => sync.onResume(), () => maintain()]);
    verifyNever(() => sync.reconcileNow(any()));
  });

  test('a gap of exactly two minutes is not a wake', () async {
    await heartbeat.beat();
    clock.advance(DesktopHeartbeat.wakeGap);
    await heartbeat.beat();
    verifyNothingExtra();
  });

  test('wall clock going backwards counts as a wake', () async {
    await heartbeat.beat();
    clock.advance(const Duration(seconds: -30));
    await heartbeat.beat();
    verify(() => sync.onResume()).called(1);
    verify(() => maintain()).called(1);
  });

  test('crossing local midnight resumes and maintains', () async {
    clock.current = at(cairo, 2026, 10, 9, 23, 59, 30);
    heartbeat = DesktopHeartbeat(clock, alarm, sync, maintain, _FixedLocation())..start();
    await heartbeat.beat();
    clock.current = at(cairo, 2026, 10, 10, 0, 0, 30);
    await heartbeat.beat();
    verify(() => sync.onResume()).called(1);
    verify(() => maintain()).called(1);
  });

  test('after an hour the periodic reconcile runs with maintenance; the counter then resets', () async {
    await heartbeat.beat();
    for (var i = 0; i < 59; i++) {
      clock.advance(DesktopHeartbeat.period);
      await heartbeat.beat();
    }
    verifyNothingExtra();
    clock.advance(DesktopHeartbeat.period);
    await heartbeat.beat();
    verifyInOrder([() => alarm.tick(), () => sync.reconcileNow(ReconcileTrigger.periodic), () => maintain()]);
    clearInteractions(sync);
    clock.advance(DesktopHeartbeat.period);
    await heartbeat.beat();
    verifyNever(() => sync.reconcileNow(any()));
    verifyNever(() => sync.onResume());
  });

  test('a wake resets the hour counter', () async {
    await heartbeat.beat();
    clock.advance(const Duration(minutes: 50));
    await heartbeat.beat(); // wake
    clock.advance(const Duration(minutes: 1));
    await heartbeat.beat();
    clock.advance(const Duration(minutes: 20));
    await heartbeat.beat(); // wake again (gap > 2 min), still no periodic
    verifyNever(() => sync.reconcileNow(any()));
    verify(() => sync.onResume()).called(2);
  });

  test('alarm ticks before resume', () async {
    await heartbeat.beat();
    clock.advance(const Duration(hours: 1));
    await heartbeat.beat();
    verifyInOrder([() => alarm.tick(), () => alarm.tick(), () => sync.onResume()]);
  });

  test('a throwing step neither stops later steps nor throws', () async {
    when(() => alarm.tick()).thenThrow(StateError('tick'));
    when(() => sync.onResume()).thenThrow(StateError('resume'));
    await heartbeat.beat();
    clock.advance(const Duration(minutes: 5));
    await expectLater(heartbeat.beat(), completes);
    verify(() => sync.onResume()).called(1);
    verify(() => maintain()).called(1);
    // Later beats still work.
    clock.advance(DesktopHeartbeat.period);
    await heartbeat.beat();
    verify(() => alarm.tick()).called(3);
  });

  test('overlapping beats are skipped', () async {
    final gate = Future<void>.delayed(const Duration(milliseconds: 20));
    when(() => alarm.tick()).thenAnswer((_) => gate);
    await Future.wait([heartbeat.beat(), heartbeat.beat()]);
    verify(() => alarm.tick()).called(1);
  });

  group('delayUntilNextBeat', () {
    Duration d(int s, [int ms = 0]) => DesktopHeartbeat.delayUntilNextBeat(at(cairo, 2026, 10, 9, 10, 0, s, ms));

    test('aligns to minute boundary + 1 s', () {
      expect(d(0), const Duration(seconds: 1));
      expect(d(0, 500), const Duration(milliseconds: 500));
      expect(d(1), const Duration(seconds: 60));
      expect(d(30), const Duration(seconds: 31));
      expect(d(59, 500), const Duration(milliseconds: 1500));
    });

    test('is always in (0, 61 s]', () {
      for (var s = 0; s < 60; s++) {
        final delay = d(s, 999);
        expect(delay, greaterThan(Duration.zero));
        expect(delay, lessThanOrEqualTo(const Duration(seconds: 61)));
      }
    });
  });

  test('start arms a timer and beats fire under fake_async, re-armed each time', () {
    fakeAsync((async) {
      final c = FixedClock(at(cairo, 2026, 10, 9, 10, 0, 30));
      final h = DesktopHeartbeat(c, alarm, sync, maintain, _FixedLocation())
        ..start()
        ..start(); // idempotent
      void elapse(Duration d) {
        c.advance(d);
        async.elapse(d);
      }

      elapse(const Duration(seconds: 30)); // 10:01:00, not yet
      verifyNever(() => alarm.tick());
      elapse(const Duration(seconds: 1)); // 10:01:01
      verify(() => alarm.tick()).called(1);
      elapse(const Duration(seconds: 60));
      verify(() => alarm.tick()).called(1);
      h.dispose();
      elapse(const Duration(minutes: 5));
      verifyNever(() => alarm.tick());
    });
  });
}
