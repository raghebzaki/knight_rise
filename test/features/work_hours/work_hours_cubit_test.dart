import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:knight_rise/features/work_hours/presentation/work_hours_cubit.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeWorkScheduleRepository repo;
  late WorkHoursCubit cubit;

  setUp(() async {
    repo = FakeWorkScheduleRepository();
    cubit = WorkHoursCubit(repo);
    await cubit.load();
  });

  tearDown(() => cubit.close());

  test('load: Sun-Thu on, Fri/Sat off, not dirty', () {
    expect(cubit.state.loaded, isTrue);
    expect(cubit.state.enabled, {7, 1, 2, 3, 4});
    expect(cubit.state.windowsOf(DateTime.friday), isEmpty);
    expect(cubit.state.isDirty, isFalse);
    expect(cubit.state.canSave, isFalse);
  });

  test('turning a day off keeps its windows; turning it on restores them', () {
    cubit
      ..updateWindow(DateTime.monday, 0, 8 * 60, 12 * 60)
      ..setDayEnabled(DateTime.monday, enabled: false)
      ..setDayEnabled(DateTime.monday, enabled: true);
    expect(cubit.state.windowsOf(DateTime.monday), [TimeWindow.hm(8, 0, 12, 0)]);

    cubit.setDayEnabled(DateTime.monday, enabled: false);
    expect(cubit.state.windowsOf(DateTime.monday), isNotEmpty);
    expect(cubit.state.schedule.days.containsKey(DateTime.monday), isFalse);
  });

  test('turning on a day without windows gives it 09:00-17:00', () {
    cubit.setDayEnabled(DateTime.friday, enabled: true);
    expect(cubit.state.schedule.days[DateTime.friday], [TimeWindow.hm(9, 0, 17, 0)]);
  });

  test('addWindow: one hour after the last end, 60 minutes long', () {
    expect(cubit.addWindow(DateTime.sunday), isTrue);
    expect(cubit.state.windowsOf(DateTime.sunday), [TimeWindow.hm(9, 0, 17, 0), TimeWindow.hm(18, 0, 19, 0)]);
  });

  test('addWindow refuses when it would pass midnight or exceed four windows', () {
    cubit.updateWindow(DateTime.sunday, 0, 9 * 60, 23 * 60);
    expect(cubit.state.canAddWindow(DateTime.sunday), isFalse);
    expect(cubit.addWindow(DateTime.sunday), isFalse);

    cubit.updateWindow(DateTime.sunday, 0, 6 * 60, 7 * 60);
    expect(cubit.addWindow(DateTime.sunday), isTrue); // 08-09
    expect(cubit.addWindow(DateTime.sunday), isTrue); // 10-11
    expect(cubit.addWindow(DateTime.sunday), isTrue); // 12-13
    expect(cubit.state.windowsOf(DateTime.sunday), hasLength(4));
    expect(cubit.addWindow(DateTime.sunday), isFalse);
  });

  test('updateWindow edits and keeps windows sorted; rejects bad ranges', () {
    cubit.addWindow(DateTime.sunday);
    expect(cubit.updateWindow(DateTime.sunday, 1, 6 * 60, 7 * 60), isTrue);
    expect(cubit.state.windowsOf(DateTime.sunday).first, TimeWindow.hm(6, 0, 7, 0));

    final before = cubit.state;
    expect(cubit.updateWindow(DateTime.sunday, 0, 10 * 60, 10 * 60), isFalse);
    expect(cubit.updateWindow(DateTime.sunday, 5, 10 * 60, 11 * 60), isFalse);
    expect(cubit.state, before);
  });

  test('removeWindow deletes by index', () {
    cubit
      ..addWindow(DateTime.sunday)
      ..removeWindow(DateTime.sunday, 0);
    expect(cubit.state.windowsOf(DateTime.sunday), [TimeWindow.hm(18, 0, 19, 0)]);
  });

  test('copySundayToWorkDays copies to on-days only', () {
    cubit
      ..updateWindow(DateTime.sunday, 0, 8 * 60, 12 * 60)
      ..addWindow(DateTime.sunday)
      ..copySundayToWorkDays();
    final sunday = cubit.state.windowsOf(DateTime.sunday);
    expect(cubit.state.windowsOf(DateTime.wednesday), sunday);
    expect(cubit.state.windowsOf(DateTime.friday), isEmpty); // off day untouched
    expect(cubit.state.enabled, {7, 1, 2, 3, 4});
  });

  test('copySundayToWorkDays is a no-op while Sunday is off', () {
    cubit.setDayEnabled(DateTime.sunday, enabled: false);
    final before = cubit.state;
    cubit.copySundayToWorkDays();
    expect(cubit.state, before);
  });

  test('presets set the work days and keep other days windows in the draft', () {
    cubit.applyMonFri();
    expect(cubit.state.enabled, {1, 2, 3, 4, 5});
    expect(cubit.state.schedule.days[DateTime.friday], [TimeWindow.hm(9, 0, 17, 0)]);
    expect(cubit.state.schedule.days.containsKey(DateTime.sunday), isFalse);
    cubit.applySunThu();
    expect(cubit.state.schedule, WorkSchedule.standard());
    expect(cubit.state.isDirty, isFalse);
  });

  test('save persists a valid draft and clears dirty', () async {
    cubit.applyMonFri();
    expect(cubit.state.canSave, isTrue);
    expect(await cubit.save(), isTrue);
    expect(repo.current.days.keys.toSet(), {1, 2, 3, 4, 5});
    expect(cubit.state.isDirty, isFalse);
    expect(await cubit.save(), isFalse); // nothing left to save
  });

  test('save refuses an invalid draft', () async {
    cubit
      ..addWindow(DateTime.sunday)
      ..updateWindow(DateTime.sunday, 1, 16 * 60, 18 * 60);
    expect(cubit.state.isValid, isFalse);
    expect(cubit.state.canSave, isFalse);
    expect(await cubit.save(), isFalse);
    expect(repo.current, WorkSchedule.standard());
  });

  test('a day with a short window is invalid', () {
    cubit.updateWindow(DateTime.monday, 0, 9 * 60, 9 * 60 + 10);
    expect(cubit.state.issuesFor(DateTime.monday), hasLength(1));
    expect(cubit.state.issuesFor(DateTime.tuesday), isEmpty);
  });

  test('off days do not make the draft invalid', () {
    cubit
      ..updateWindow(DateTime.monday, 0, 9 * 60, 9 * 60 + 10)
      ..setDayEnabled(DateTime.monday, enabled: false);
    expect(cubit.state.isValid, isTrue);
  });
}
