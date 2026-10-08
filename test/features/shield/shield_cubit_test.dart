import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:knight_rise/features/shield/presentation/shield_cubit.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';
import 'package:knight_rise/features/work_hours/domain/usecases/day_override_usecases.dart';

import '../../helpers/fakes.dart';
import '../../helpers/tz.dart';

void main() {
  late FakeShieldRepository shields;
  late FakeDayOverrideRepository overrides;
  late FakeWorkScheduleRepository work;
  late FixedClock clock;
  late ShieldCubit cubit;
  late List<ShieldMessage> messages;

  ShieldCubit build() {
    final location = FakeLocationProvider(cairo);
    return ShieldCubit(
      StartShield(shields, work, overrides, const ReminderPlanner(), clock, location),
      ExtendShield(shields, clock),
      EndShield(shields, clock),
      SetDayOff(overrides),
      ExtendWorkDay(overrides),
      ClearDayOverride(overrides),
      clock,
      location,
    );
  }

  setUp(() {
    shields = FakeShieldRepository();
    overrides = FakeDayOverrideRepository();
    work = FakeWorkScheduleRepository();
    clock = FixedClock(at(cairo, 2026, 10, 5, 9, 30)); // Monday, on duty
    cubit = build();
    messages = [];
    cubit.messages.listen(messages.add);
  });

  tearDown(() => cubit.close());

  test('presets start Shields with the right length and reason', () async {
    final now = clock.now();
    await cubit.start(ShieldPreset.min25);
    expect(shields.all.single.endAt, now.add(const Duration(minutes: 25)));
    expect(shields.all.single.reason, ShieldReason.focus);

    await cubit.start(ShieldPreset.min50);
    expect(shields.all.last.endAt, now.add(const Duration(minutes: 50)));
    expect(shields.all.last.reason, ShieldReason.meeting);

    await cubit.start(ShieldPreset.untilOff);
    expect(shields.all.last.endAt, at(cairo, 2026, 10, 5, 17));
    expect(shields.all.last.reason, ShieldReason.untilOff);

    await cubit.start(ShieldPreset.custom, custom: const Duration(minutes: 90));
    expect(shields.all.last.endAt, now.add(const Duration(minutes: 90)));
    expect(shields.all.last.reason, ShieldReason.custom);
    expect(messages, isEmpty);
  });

  test('a refused start (until-off off duty) emits one message and stores nothing', () async {
    clock.current = at(cairo, 2026, 10, 10, 12); // Saturday
    await cubit.start(ShieldPreset.untilOff);
    await Future<void>.delayed(Duration.zero);
    expect(shields.all, isEmpty);
    expect(messages, [ShieldMessage.shieldUnavailable]);
  });

  test('extend adds 15 minutes by default; end stops the Shield', () async {
    await cubit.start(ShieldPreset.min25);
    final end = shields.all.single.endAt;
    await cubit.extend();
    expect(shields.all.single.endAt, end.add(const Duration(minutes: 15)));

    await cubit.end();
    expect(shields.all.single.endedAt, clock.now());
  });

  test('day off, working late and clear use today in Cairo', () async {
    await cubit.dayOffToday();
    expect(overrides.all.single.date, DateTime.utc(2026, 10, 5));
    expect(overrides.all.single.kind, DayOverrideKind.off);

    await cubit.workLateToday();
    await cubit.workLateToday();
    expect(overrides.all.single.kind, DayOverrideKind.extend);
    expect(overrides.all.single.extendMinutes, 120);

    await cubit.clearToday();
    expect(overrides.all, isEmpty);
  });

  test("today's date is the Cairo date even when UTC is still yesterday", () async {
    clock.current = DateTime.utc(2026, 10, 5, 22, 30); // 00:30 on Oct 6 in Cairo (UTC+2)
    await cubit.dayOffToday();
    expect(overrides.all.single.date, DateTime.utc(2026, 10, 6));
  });
}
