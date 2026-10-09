import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/config/background_ids.dart';
import 'package:knight_rise/features/scheduler/data/background_tasks.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/services/schedule_reconciler.dart';
import 'package:mocktail/mocktail.dart';
import 'package:workmanager/workmanager.dart';

import '../../helpers/fakes.dart';

class _MockAdapter extends Mock implements WorkmanagerAdapter;

class _ErrorReconciler implements ScheduleReconciler {
  @override
  Future<ReconcileRun> reconcile(ReconcileTrigger trigger) async =>
      ReconcileRun(at: DateTime(2026), trigger: trigger, planned: 0, added: 0, cancelled: 0, error: 'boom');
}

void main() {
  group('runBackgroundTask', () {
    test('bootstraps once, reconciles with periodic, returns true', () async {
      final reconciler = FakeScheduleReconciler();
      var bootstraps = 0;
      final ok = await runBackgroundTask(
        'whatever-name',
        bootstrap: () async => bootstraps++,
        reconciler: () async => reconciler,
        maintainHistory: () async {},
      );
      expect(ok, isTrue);
      expect(bootstraps, 1);
      expect(reconciler.calls, [ReconcileTrigger.periodic]);
    });

    test('returns true when the run recorded an error', () async {
      final ok = await runBackgroundTask(
        't',
        bootstrap: () async {},
        reconciler: () async => _ErrorReconciler(),
        maintainHistory: () async {},
      );
      expect(ok, isTrue);
    });

    test('returns true when reconcile throws', () async {
      final reconciler = FakeScheduleReconciler()..throwOnNext = StateError('x');
      final ok = await runBackgroundTask(
        't',
        bootstrap: () async {},
        reconciler: () async => reconciler,
        maintainHistory: () async {},
      );
      expect(ok, isTrue);
    });

    test('returns false and skips reconcile when bootstrap throws', () async {
      final reconciler = FakeScheduleReconciler();
      final ok = await runBackgroundTask(
        't',
        bootstrap: () async => throw StateError('no db'),
        reconciler: () async => reconciler,
        maintainHistory: () async {},
      );
      expect(ok, isFalse);
      expect(reconciler.calls, isEmpty);
    });
  });

  group('runBackgroundTask history maintenance', () {
    test('runs after the reconcile', () async {
      final reconciler = FakeScheduleReconciler();
      List<ReconcileTrigger>? seen;
      final ok = await runBackgroundTask(
        't',
        bootstrap: () async {},
        reconciler: () async => reconciler,
        maintainHistory: () async => seen = [...reconciler.calls],
      );
      expect(ok, isTrue);
      expect(seen, [ReconcileTrigger.periodic]);
    });

    test('still runs when the reconcile throws', () async {
      var ran = false;
      final ok = await runBackgroundTask(
        't',
        bootstrap: () async {},
        reconciler: () async => FakeScheduleReconciler()..throwOnNext = StateError('x'),
        maintainHistory: () async => ran = true,
      );
      expect(ok, isTrue);
      expect(ran, isTrue);
    });

    test('a failure is logged and the task still succeeds', () async {
      final ok = await runBackgroundTask(
        't',
        bootstrap: () async {},
        reconciler: () async => FakeScheduleReconciler(),
        maintainHistory: () async => throw StateError('db'),
      );
      expect(ok, isTrue);
    });

    test('is skipped when bootstrap fails', () async {
      var ran = false;
      final ok = await runBackgroundTask(
        't',
        bootstrap: () async => throw StateError('no db'),
        reconciler: () async => FakeScheduleReconciler(),
        maintainHistory: () async => ran = true,
      );
      expect(ok, isFalse);
      expect(ran, isFalse);
    });
  });

  group('WorkmanagerBackgroundScheduler.register', () {
    late _MockAdapter adapter;

    setUpAll(() {
      registerFallbackValue(() {});
      registerFallbackValue(Duration.zero);
      registerFallbackValue(Constraints());
      registerFallbackValue(ExistingPeriodicWorkPolicy.keep);
      registerFallbackValue(BackoffPolicy.linear);
    });

    setUp(() {
      adapter = _MockAdapter();
      when(() => adapter.initialize(any())).thenAnswer((_) async {});
      when(
        () => adapter.registerPeriodicTask(
          any(),
          any(),
          frequency: any(named: 'frequency'),
          initialDelay: any(named: 'initialDelay'),
          constraints: any(named: 'constraints'),
          existingWorkPolicy: any(named: 'existingWorkPolicy'),
          backoffPolicy: any(named: 'backoffPolicy'),
          backoffPolicyDelay: any(named: 'backoffPolicyDelay'),
        ),
      ).thenAnswer((_) async {});
    });

    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('android: initialize then periodic task with update policy', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await WorkmanagerBackgroundScheduler(adapter).register();
      verifyInOrder([
        () => adapter.initialize(knightCallbackDispatcher),
        () => adapter.registerPeriodicTask(
          BackgroundIds.androidReconcileUniqueName,
          BackgroundIds.reconcileTaskName,
          frequency: const Duration(hours: 1),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
          constraints: any(named: 'constraints'),
          backoffPolicy: BackoffPolicy.exponential,
          backoffPolicyDelay: any(named: 'backoffPolicyDelay'),
        ),
      ]);
      verifyNoMoreInteractions(adapter);
    });

    test('iOS: initialize then BGAppRefresh periodic task', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await WorkmanagerBackgroundScheduler(adapter).register();
      verifyInOrder([
        () => adapter.initialize(knightCallbackDispatcher),
        () => adapter.registerPeriodicTask(
          BackgroundIds.iosReconcileTask,
          BackgroundIds.reconcileTaskName,
          frequency: const Duration(hours: 1),
          initialDelay: const Duration(hours: 1),
        ),
      ]);
      verifyNoMoreInteractions(adapter);
    });

    test('adapter failures are swallowed', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      when(() => adapter.initialize(any())).thenThrow(StateError('plugin missing'));
      await expectLater(WorkmanagerBackgroundScheduler(adapter).register(), completes);
    });
  });

  test('DesktopBackgroundScheduler registers nothing and completes', () async {
    await expectLater(const DesktopBackgroundScheduler().register(), completes);
  });
}
