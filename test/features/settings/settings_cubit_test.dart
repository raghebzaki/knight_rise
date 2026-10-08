import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/settings/presentation/settings_cubit.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeSettingsRepository settings;
  late FakeWorkScheduleRepository work;
  late SettingsCubit cubit;

  setUp(() {
    settings = FakeSettingsRepository();
    work = FakeWorkScheduleRepository();
    cubit = SettingsCubit(settings, work);
  });

  tearDown(() => cubit.close());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('loads settings and schedule', () async {
    expect(cubit.state.loaded, isFalse);
    await settle();
    expect(cubit.state.loaded, isTrue);
    expect(cubit.state.settings.shieldRecoverOnExit, isTrue);
    expect(cubit.state.schedule, WorkSchedule.standard());
  });

  test('setShieldRecoverOnExit saves through the repository and keeps other fields', () async {
    await settle();
    await settings.save(settings.current.copyWith(precisionTiming: true));
    await cubit.setShieldRecoverOnExit(value: false);
    await settle();
    expect(settings.current.shieldRecoverOnExit, isFalse);
    expect(settings.current.precisionTiming, isTrue);
    expect(cubit.state.settings.shieldRecoverOnExit, isFalse);
  });

  test('follows work schedule changes', () async {
    await settle();
    await work.save(const WorkSchedule());
    await settle();
    expect(cubit.state.schedule.isEmpty, isTrue);
  });
}
