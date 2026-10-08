import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/routines/presentation/routine_editor_cubit.dart';
import 'package:knight_rise/features/routines/presentation/routines_cubit.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeRoutineRepository repo;
  late FakeSettingsRepository settings;

  setUp(() {
    repo = FakeRoutineRepository();
    settings = FakeSettingsRepository();
  });

  Future<RoutineEditorCubit> editor(RoutineType type) async {
    final cubit = RoutineEditorCubit(repo, settings, type);
    addTearDown(cubit.close);
    await cubit.load();
    return cubit;
  }

  test('load: draft equals saved, nothing to save', () async {
    final cubit = await editor(RoutineType.hydration);
    expect(cubit.state.loaded, isTrue);
    expect(cubit.state.draft, Routine.defaults.first);
    expect(cubit.state.isDirty, isFalse);
    expect(cubit.state.canSave, isFalse);
    expect(cubit.state.waterPerTapMl, 250);
  });

  test('interval clamps to the routine range and snaps to 5 minutes', () async {
    final cubit = await editor(RoutineType.hydration); // 15..120
    cubit.setInterval(5);
    expect(cubit.state.draft!.intervalMinutes, 15);
    cubit.setInterval(500);
    expect(cubit.state.draft!.intervalMinutes, 120);
    cubit.setInterval(52);
    expect(cubit.state.draft!.intervalMinutes, 50);
    cubit.setInterval(53);
    expect(cubit.state.draft!.intervalMinutes, 55);
  });

  test('each routine respects its own bounds', () async {
    final stretch = await editor(RoutineType.stretch)
      ..setInterval(10);
    expect(stretch.state.draft!.intervalMinutes, 30);
    final eye = await editor(RoutineType.eyeRest)
      ..setInterval(90);
    expect(eye.state.draft!.intervalMinutes, 60);
  });

  test('target stays within 1..24', () async {
    final cubit = await editor(RoutineType.stretch);
    cubit.setTarget(0);
    expect(cubit.state.draft!.dailyTarget, 1);
    cubit.decrementTarget();
    expect(cubit.state.draft!.dailyTarget, 1);
    cubit.setTarget(99);
    expect(cubit.state.draft!.dailyTarget, 24);
    cubit.incrementTarget();
    expect(cubit.state.draft!.dailyTarget, 24);
    cubit.decrementTarget();
    expect(cubit.state.draft!.dailyTarget, 23);
  });

  test('save persists the draft only on explicit save', () async {
    final cubit = await editor(RoutineType.hydration);
    cubit
      ..setEnabled(enabled: false)
      ..setInterval(60)
      ..setTarget(10)
      ..setMode(ScheduleMode.fixedGrid);
    expect((await repo.getAll()).first, Routine.defaults.first);
    expect(cubit.state.canSave, isTrue);

    expect(await cubit.save(), isTrue);
    final saved = (await repo.getAll()).first;
    expect(saved.enabled, isFalse);
    expect(saved.intervalMinutes, 60);
    expect(saved.dailyTarget, 10);
    expect(saved.mode, ScheduleMode.fixedGrid);
    expect(cubit.state.isDirty, isFalse);
    expect(await cubit.save(), isFalse);
  });

  test('reverting to the saved values clears dirty', () async {
    final cubit = await editor(RoutineType.hydration);
    cubit.setTarget(9);
    expect(cubit.state.isDirty, isTrue);
    cubit.setTarget(8);
    expect(cubit.state.isDirty, isFalse);
  });

  test('RoutinesCubit lists routines and toggles one', () async {
    final cubit = RoutinesCubit(repo);
    addTearDown(cubit.close);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state, hasLength(3));
    await cubit.setEnabled(RoutineType.stretch, enabled: false);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state!.firstWhere((r) => r.type == RoutineType.stretch).enabled, isFalse);
    expect(cubit.state!.where((r) => r.enabled), hasLength(2));
  });
}
