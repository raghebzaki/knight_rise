import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';
import 'package:knight_rise/features/onboarding/presentation/onboarding_cubit.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';

import '../../helpers/fakes.dart';
import '../../helpers/health_fakes.dart';

void main() {
  late FakeRoutineRepository routines;
  late FakeWorkScheduleRepository schedule;
  late FakeSettingsRepository settings;
  late FakeScheduleReconciler reconciler;
  late FakeLaunchAtLogin launch;
  late OnboardingCubit cubit;

  OnboardingCubit build() => OnboardingCubit(routines, schedule, settings, reconciler, launch);

  setUp(() async {
    routines = FakeRoutineRepository();
    schedule = FakeWorkScheduleRepository();
    settings = FakeSettingsRepository();
    reconciler = FakeScheduleReconciler();
    launch = FakeLaunchAtLogin(LaunchAtLoginStatus.disabled);
    cubit = build();
    addTearDown(cubit.close);
    await cubit.load();
  });

  test('loads defaults from the repositories', () {
    final s = cubit.state;
    expect(s.loaded, isTrue);
    expect(s.step, OnboardingStep.welcome);
    expect(s.routines, Routine.defaults);
    expect(s.preset, WorkDaysPreset.sunThu);
    expect(s.days, {7, 1, 2, 3, 4});
    expect((s.startMinute, s.endMinute), (540, 1020));
    expect(s.schedule, WorkSchedule.standard());
  });

  test('a stored Mon-Fri schedule selects that preset; a mixed one falls back to defaults', () async {
    schedule = FakeWorkScheduleRepository(
      WorkSchedule(
        days: {
          for (final d in [1, 2, 3, 4, 5]) d: [TimeWindow.hm(8, 0, 16, 0)],
        },
      ),
    );
    final other = build();
    addTearDown(other.close);
    await other.load();
    expect(other.state.preset, WorkDaysPreset.monFri);
    expect((other.state.startMinute, other.state.endMinute), (480, 960));

    schedule = FakeWorkScheduleRepository(
      WorkSchedule(
        days: {
          1: [TimeWindow.hm(8, 0, 12, 0), TimeWindow.hm(13, 0, 17, 0)],
        },
      ),
    );
    final split = build();
    addTearDown(split.close);
    await split.load();
    expect(split.state.preset, WorkDaysPreset.sunThu);
    expect((split.state.startMinute, split.state.endMinute), (540, 1020));
  });

  test('routine toggles, intervals and the at-least-one rule', () {
    cubit.next();
    expect(cubit.state.step, OnboardingStep.routines);
    cubit.setInterval(RoutineType.hydration, 30);
    expect(cubit.state.routine(RoutineType.hydration)!.intervalMinutes, 30);
    cubit.setInterval(RoutineType.eyeRest, 500); // out of range: ignored
    expect(cubit.state.routine(RoutineType.eyeRest)!.intervalMinutes, 20);

    for (final t in RoutineType.values) {
      cubit.setRoutineEnabled(t, enabled: false);
    }
    expect(cubit.state.hasEnabledRoutine, isFalse);
    expect(cubit.state.canAdvance, isFalse);
    cubit.next();
    expect(cubit.state.step, OnboardingStep.routines);

    cubit.setRoutineEnabled(RoutineType.stretch, enabled: true);
    expect(cubit.state.canAdvance, isTrue);
    cubit.next();
    expect(cubit.state.step, OnboardingStep.workHours);
  });

  test('interval options stay inside each routine range', () {
    for (final t in RoutineType.values) {
      final range = Routine.intervalRange(t);
      for (final m in OnboardingCubit.intervalOptions(t)) {
        expect(m, inInclusiveRange(range.min, range.max));
      }
    }
  });

  test('back stops at the first step', () {
    cubit
      ..next()
      ..back()
      ..back();
    expect(cubit.state.step, OnboardingStep.welcome);
  });

  test('presets and custom days', () {
    cubit.setPreset(WorkDaysPreset.monFri);
    expect(cubit.state.days, {1, 2, 3, 4, 5});
    cubit.toggleDay(6); // ignored outside custom
    expect(cubit.state.days, {1, 2, 3, 4, 5});

    cubit
      ..setPreset(WorkDaysPreset.custom)
      ..toggleDay(5)
      ..toggleDay(6);
    expect(cubit.state.preset, WorkDaysPreset.custom);
    expect(cubit.state.days, {1, 2, 3, 4, 6});

    cubit.setPreset(WorkDaysPreset.sunThu);
    expect(cubit.state.days, {7, 1, 2, 3, 4});

    cubit.setPreset(WorkDaysPreset.custom);
    [7, 1, 2, 3, 4].forEach(cubit.toggleDay);
    expect(cubit.state.workHoursProblem, WorkHoursProblem.noDays);
  });

  test('time validation: end after start and at least 30 minutes', () {
    cubit.setEnd(540);
    expect(cubit.state.workHoursProblem, WorkHoursProblem.endNotAfterStart);
    expect(cubit.state.schedule.isEmpty, isTrue);
    cubit.setEnd(555);
    expect(cubit.state.workHoursProblem, WorkHoursProblem.tooShort);
    cubit.setEnd(570);
    expect(cubit.state.workHoursProblem, isNull);
    cubit.setStart(600);
    expect(cubit.state.workHoursProblem, WorkHoursProblem.endNotAfterStart);
    cubit.setEnd(1440);
    expect(cubit.state.workHoursProblem, isNull);
  });

  test('step 3 cannot advance with invalid hours', () {
    cubit
      ..next()
      ..next()
      ..setEnd(100);
    expect(cubit.state.step, OnboardingStep.workHours);
    expect(cubit.state.canAdvance, isFalse);
    cubit.next();
    expect(cubit.state.step, OnboardingStep.workHours);
  });

  test('nothing is saved before finish', () {
    cubit
      ..setInterval(RoutineType.hydration, 90)
      ..setPreset(WorkDaysPreset.monFri);
    expect(routines.getAll(), completion(Routine.defaults));
    expect(schedule.current, WorkSchedule.standard());
    expect(settings.current.onboardingCompleted, isFalse);
    expect(reconciler.calls, isEmpty);
  });

  test('finish saves routines, hours, completed flag and reconciles once', () async {
    cubit
      ..setInterval(RoutineType.hydration, 90)
      ..setRoutineEnabled(RoutineType.stretch, enabled: false)
      ..setPreset(WorkDaysPreset.monFri)
      ..setStart(8 * 60)
      ..setEnd(16 * 60);
    expect(await cubit.finish(), isTrue);

    final saved = await routines.getAll();
    expect(saved.firstWhere((r) => r.type == RoutineType.hydration).intervalMinutes, 90);
    expect(saved.firstWhere((r) => r.type == RoutineType.stretch).enabled, isFalse);
    expect(saved.firstWhere((r) => r.type == RoutineType.eyeRest), Routine.defaults.last);
    expect(
      schedule.current,
      WorkSchedule(
        days: {
          for (final d in [1, 2, 3, 4, 5]) d: [TimeWindow.hm(8, 0, 16, 0)],
        },
      ),
    );
    expect(settings.current.onboardingCompleted, isTrue);
    expect(reconciler.calls, [ReconcileTrigger.manual]);
  });

  test('finish keeps other settings and refuses invalid drafts', () async {
    cubit.setEnd(0);
    expect(await cubit.finish(), isFalse);
    expect(settings.current.onboardingCompleted, isFalse);
    expect(reconciler.calls, isEmpty);

    cubit.setEnd(1020);
    await settings.save(settings.current.copyWith(waterPerTapMl: 300, localeCode: 'ar'));
    expect(await cubit.finish(), isTrue);
    expect(settings.current.waterPerTapMl, 300);
    expect(settings.current.localeCode, 'ar', reason: 'the language chosen on step 0 is kept');
  });

  test('double finish saves and reconciles once', () async {
    reconciler.delay = const Duration(milliseconds: 10);
    final first = cubit.finish();
    final second = cubit.finish();
    expect(await second, isFalse);
    expect(await first, isTrue);
    expect(await cubit.finish(), isFalse);
    expect(reconciler.calls, hasLength(1));
  });

  test('a reconcile failure does not undo onboarding', () async {
    reconciler.throwOnNext = StateError('boom');
    expect(await cubit.finish(), isTrue);
    expect(settings.current.onboardingCompleted, isTrue);
  });

  group('launch at login (desktop)', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('defaults to on and finish applies it after saving', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(cubit.state.launchAtLogin, isTrue);
      expect(await cubit.finish(), isTrue);
      expect(launch.sets, [true]);
      expect(settings.current.onboardingCompleted, isTrue);
    });

    test('opting out applies false', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      cubit.setLaunchAtLogin(value: false);
      expect(await cubit.finish(), isTrue);
      expect(launch.sets, [false]);
    });

    test('a failing registration never blocks finishing', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      launch.throwOnSet = StateError('boom');
      expect(await cubit.finish(), isTrue);
      expect(settings.current.onboardingCompleted, isTrue);
      expect(reconciler.calls, [ReconcileTrigger.manual]);
    });

    test('an invalid draft does not touch the login item', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      for (final t in RoutineType.values) {
        cubit.setRoutineEnabled(t, enabled: false);
      }
      expect(await cubit.finish(), isFalse);
      expect(launch.sets, isEmpty);
    });

    test('mobile never calls it', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await cubit.finish(), isTrue);
      expect(launch.sets, isEmpty);
    });
  });
}
