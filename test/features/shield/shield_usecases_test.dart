import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/fakes.dart';
import '../../helpers/tz.dart';

// Monday 2026-10-05 is a work day (09:00-17:00); Friday the 9th is off.
tz.TZDateTime t(int h, [int m = 0, int day = 5]) => at(cairo, 2026, 10, day, h, m);

void main() {
  late FakeShieldRepository shields;
  late FakeWorkScheduleRepository work;
  late FakeDayOverrideRepository overrides;
  late FixedClock clock;
  late StartShield start;
  late ExtendShield extend;
  late EndShield end;

  setUp(() {
    shields = FakeShieldRepository();
    work = FakeWorkScheduleRepository();
    overrides = FakeDayOverrideRepository();
    clock = FixedClock(t(10));
    start = StartShield(shields, work, overrides, const ReminderPlanner(), clock, FakeLocationProvider(cairo));
    extend = ExtendShield(shields, clock);
    end = EndShield(shields, clock);
  });

  group('StartShield', () {
    test('25 min preset', () async {
      final s = await start(ShieldPreset.min25);
      expect(s, isNotNull);
      expect(s!.id, 1);
      expect(s.startAt, t(10));
      expect(s.endAt, t(10, 25));
      expect(s.reason, ShieldReason.focus);
      expect(shields.all.single, s);
    });

    test('50 min preset', () async {
      final s = await start(ShieldPreset.min50);
      expect(s!.endAt, t(10, 50));
      expect(s.reason, ShieldReason.meeting);
    });

    test('custom preset has no cap, even past the end of the work day', () async {
      clock.current = t(16, 30);
      final s = await start(ShieldPreset.custom, custom: const Duration(hours: 5));
      expect(s!.endAt, t(21, 30));
      expect(s.reason, ShieldReason.custom);
    });

    test('custom preset needs a positive duration', () {
      expect(() => start(ShieldPreset.custom), throwsArgumentError);
      expect(() => start(ShieldPreset.custom, custom: Duration.zero), throwsArgumentError);
    });

    test('presets work outside work hours (no cap, no window needed)', () async {
      clock.current = t(21);
      expect((await start(ShieldPreset.min25))!.endAt, t(21, 25));
    });

    test('untilOff ends at the end of the current work window', () async {
      final s = await start(ShieldPreset.untilOff);
      expect(s!.endAt, t(17));
      expect(s.reason, ShieldReason.untilOff);
    });

    test('untilOff in a split shift ends the current window, not the day', () async {
      await work.save(
        work.current.copyWith(
          days: {
            ...work.current.days,
            1: [
              work.current.days[1]!.first.copyWith(endMinute: 12 * 60),
              work.current.days[1]!.first.copyWith(startMinute: 13 * 60),
            ],
          },
        ),
      );
      final s = await start(ShieldPreset.untilOff);
      expect(s!.endAt, t(12));
    });

    test('untilOff respects an extend override', () async {
      await overrides.set(
        DayOverride(date: DateTime.utc(2026, 10, 5), kind: DayOverrideKind.extend, extendMinutes: 90),
      );
      final s = await start(ShieldPreset.untilOff);
      expect(s!.endAt, t(18, 30));
    });

    test('untilOff on a day off returns null', () async {
      await overrides.set(DayOverride(date: DateTime.utc(2026, 10, 5), kind: DayOverrideKind.off));
      expect(await start(ShieldPreset.untilOff), isNull);
      expect(shields.all, isEmpty);
    });

    test('untilOff outside work hours returns null and keeps an active Shield', () async {
      await start(ShieldPreset.custom, custom: const Duration(hours: 10));
      clock.current = t(18);
      expect(await start(ShieldPreset.untilOff), isNull);
      expect(shields.all.single.endedAt, isNull);

      clock.current = t(8, 30); // before the window, Shield from 10:00 not yet started
      expect(await start(ShieldPreset.untilOff), isNull);
      clock.current = t(10, 0, 9); // Friday
      expect(await start(ShieldPreset.untilOff), isNull);
    });

    test('starting while a Shield is active ends it at now and starts the new one', () async {
      final first = await start(ShieldPreset.min50);
      clock.current = t(10, 20);
      final second = await start(ShieldPreset.min25);

      expect(shields.all.length, 2);
      final old = shields.all.firstWhere((s) => s.id == first!.id);
      expect(old.endedAt, t(10, 20));
      expect(old.effectiveEnd, t(10, 20));
      expect(second!.startAt, t(10, 20));
      expect(second.endAt, t(10, 45));
      expect(await shields.active(clock.now()), second);
    });
  });

  group('ExtendShield', () {
    test('adds to the active session end', () async {
      await start(ShieldPreset.min25);
      clock.current = t(10, 10);
      final s = await extend(const Duration(minutes: 15));
      expect(s!.endAt, t(10, 40));
      expect(shields.all.single.endAt, t(10, 40));
      // Stacks.
      expect((await extend(const Duration(minutes: 10)))!.endAt, t(10, 50));
    });

    test('returns null when nothing is active', () async {
      expect(await extend(const Duration(minutes: 15)), isNull);
      await start(ShieldPreset.min25);
      clock.current = t(11);
      expect(await extend(const Duration(minutes: 15)), isNull);
    });
  });

  group('EndShield', () {
    test('sets endedAt = now on the active session', () async {
      await start(ShieldPreset.min50);
      clock.current = t(10, 12);
      final s = await end();
      expect(s!.endedAt, t(10, 12));
      expect(s.effectiveEnd, t(10, 12));
      expect(await shields.active(clock.now()), isNull);
    });

    test('is a no-op without an active session', () async {
      expect(await end(), isNull);
      await start(ShieldPreset.min25);
      clock.current = t(11);
      expect(await end(), isNull);
      expect(shields.all.single.endedAt, isNull);
    });
  });

  group('ShieldSession', () {
    final s = ShieldSession(startAt: t(10), endAt: t(11), reason: ShieldReason.focus);

    test('effectiveEnd and isActiveAt', () {
      expect(s.effectiveEnd, t(11));
      expect(s.isActiveAt(t(9, 59)), isFalse);
      expect(s.isActiveAt(t(10)), isTrue);
      expect(s.isActiveAt(t(10, 59)), isTrue);
      expect(s.isActiveAt(t(11)), isFalse);

      final early = s.copyWith(endedAt: t(10, 30));
      expect(early.effectiveEnd, t(10, 30));
      expect(early.isActiveAt(t(10, 29)), isTrue);
      expect(early.isActiveAt(t(10, 30)), isFalse);

      // An endedAt after the planned end changes nothing.
      expect(s.copyWith(endedAt: t(12)).effectiveEnd, t(11));
    });

    test('toWindow uses the effective end and records a manual end', () {
      expect(s.toWindow().start, t(10));
      expect(s.toWindow().end, t(11));
      expect(s.toWindow().endedAt, isNull);
      final early = s.copyWith(endedAt: t(10, 30)).toWindow();
      expect((early.start, early.end, early.endedAt), (t(10), t(10, 30), t(10, 30)));
    });
  });
}
