import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/quest_log/domain/entities/daily_summary.dart';
import 'package:knight_rise/features/quest_log/domain/services/day_summarizer.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/settings/domain/entities/app_settings.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/tz.dart';

void main() {
  const summarize = DaySummarizer();
  // Monday 2026-10-05 is a work day in the standard Sun–Thu schedule.
  final monday = DateTime.utc(2026, 10, 5);

  ReminderEvent done(tz.Location l, RoutineType t, int day, int h, {int? ml, int min = 0}) => ReminderEvent(
    type: t,
    outcome: ReminderOutcome.done,
    at: at(l, 2026, 10, day, h, min),
    waterMl: ml ?? (t == RoutineType.hydration ? 250 : null),
  );

  List<ReminderEvent> many(tz.Location l, RoutineType t, int count, {int day = 5, int? ml}) => [
    for (var i = 0; i < count; i++) done(l, t, day, 9 + i % 8, min: i ~/ 8, ml: ml),
  ];

  SummaryInputs inputs({
    List<ReminderEvent> events = const [],
    List<ShieldSession> shields = const [],
    List<DayOverride> overrides = const [],
    List<Routine> routines = Routine.defaults,
    WorkSchedule? schedule,
    AppSettings settings = const AppSettings(),
  }) => SummaryInputs(
    routines: routines,
    schedule: schedule ?? WorkSchedule.standard(),
    settings: settings,
    events: events,
    shields: shields,
    overrides: overrides,
  );

  DailySummary run(SummaryInputs i, {DateTime? date, tz.Location? location, DateTime? atTime}) {
    final l = location ?? cairo;
    return summarize(i, date: date ?? monday, location: l, at: atTime ?? at(l, 2026, 10, 6, 0, 5));
  }

  test('counts completions and water of that local day only, with the targets of the routines', () {
    final s = run(
      inputs(
        events: [
          done(cairo, RoutineType.hydration, 4, 23, min: 59), // the day before
          done(cairo, RoutineType.hydration, 5, 0), // local midnight belongs to the day
          done(cairo, RoutineType.hydration, 5, 10, ml: 500),
          done(cairo, RoutineType.stretch, 5, 11),
          ReminderEvent(type: RoutineType.stretch, outcome: ReminderOutcome.snoozed, at: at(cairo, 2026, 10, 5, 12)),
          done(cairo, RoutineType.eyeRest, 6, 0), // next local midnight is the next day
        ],
      ),
    );
    expect(s.date, monday);
    expect(s.isWorkDay, isTrue);
    expect(s.waterMl, 750);
    expect(s.waterTargetMl, 2000);
    expect(s.routines, const [
      RoutineDaySummary(type: RoutineType.hydration, done: 2, target: 8, enabled: true),
      RoutineDaySummary(type: RoutineType.stretch, done: 1, target: 6, enabled: true),
      RoutineDaySummary(type: RoutineType.eyeRest, done: 0, target: 12, enabled: true),
    ]);
    expect(s.thresholdPercent, 70);
    expect(s.qualified, isFalse);
  });

  test('a time of day on the date is ignored', () {
    expect(run(inputs(), date: DateTime(2026, 10, 5, 18)).date, monday);
  });

  test('qualifies when every enabled routine reaches 70 % (hydration in ml)', () {
    final events = [
      ...many(cairo, RoutineType.hydration, 3, ml: 500), // 1500 / 2000 ml = 75 %
      ...many(cairo, RoutineType.stretch, 5), // 5 / 6 = 83 %
      ...many(cairo, RoutineType.eyeRest, 9), // 9 / 12 = 75 %
    ];
    expect(run(inputs(events: events)).qualified, isTrue);

    // 3 glasses are only 37.5 % of 8 by count, but the ml rule counts volume.
    expect(run(inputs(events: events)).routines.first.done, 3);

    // 1250 ml is 62.5 %: one routine short breaks qualification.
    final short = [...events.skip(3), ...many(cairo, RoutineType.hydration, 5)];
    expect(run(inputs(events: short)).qualified, isFalse);
  });

  test('disabled routines are ignored for qualification but still recorded', () {
    final routines = [
      for (final r in Routine.defaults)
        if (r.type == RoutineType.eyeRest) r.copyWith(enabled: false) else r,
    ];
    final events = [...many(cairo, RoutineType.hydration, 6), ...many(cairo, RoutineType.stretch, 5)];
    final s = run(inputs(events: events, routines: routines));
    expect(s.qualified, isTrue);
    expect(s.routines.last, const RoutineDaySummary(type: RoutineType.eyeRest, done: 0, target: 12, enabled: false));
  });

  test('the threshold comes from settings and is stored with the day', () {
    final events = [
      ...many(cairo, RoutineType.hydration, 6), // 75 %
      ...many(cairo, RoutineType.stretch, 5), // 83 %
      ...many(cairo, RoutineType.eyeRest, 9), // 75 %
    ];
    final strict = run(inputs(events: events, settings: const AppSettings(streakThresholdPercent: 80)));
    expect(strict.thresholdPercent, 80);
    expect(strict.qualified, isFalse);
    expect(run(inputs(events: events, settings: const AppSettings(streakThresholdPercent: 75))).qualified, isTrue);
  });

  test('water target follows the hydration target and the ml per tap', () {
    final routines = [
      for (final r in Routine.defaults)
        if (r.type == RoutineType.hydration) r.copyWith(dailyTarget: 10) else r,
    ];
    final s = run(inputs(routines: routines, settings: const AppSettings(waterPerTapMl: 300)));
    expect(s.waterTargetMl, 3000);
  });

  group('rest days', () {
    test('a weekday without work windows is a rest day and never qualifies', () {
      final friday = DateTime.utc(2026, 10, 9);
      final events = [for (final t in RoutineType.values) ...many(cairo, t, 12, day: 9)];
      final s = run(inputs(events: events), date: friday);
      expect(s.isWorkDay, isFalse);
      expect(s.qualified, isFalse);
      expect(s.countsTowardStreak, isFalse);
      expect(s.routines.first.done, 12); // still recorded for the charts
    });

    test('a "day off" override makes a work day a rest day', () {
      final s = run(
        inputs(
          overrides: [DayOverride(date: monday, kind: DayOverrideKind.off)],
        ),
      );
      expect(s.isWorkDay, isFalse);
      expect(s.countsTowardStreak, isFalse);
    });

    test('"working late" keeps it a work day; an override on another date is ignored', () {
      final late = run(
        inputs(
          overrides: [DayOverride(date: monday, kind: DayOverrideKind.extend, extendMinutes: 60)],
        ),
      );
      expect(late.isWorkDay, isTrue);
      final other = run(
        inputs(
          overrides: [DayOverride(date: DateTime.utc(2026, 10, 6), kind: DayOverrideKind.off)],
        ),
      );
      expect(other.isWorkDay, isTrue);
    });

    test('a work day with every routine disabled is neutral', () {
      final routines = [for (final r in Routine.defaults) r.copyWith(enabled: false)];
      final s = run(inputs(routines: routines));
      expect(s.isWorkDay, isTrue);
      expect(s.qualified, isFalse);
      expect(s.countsTowardStreak, isFalse);
    });
  });

  group('focus minutes', () {
    ShieldSession shield(int sh, int sm, int eh, int em, {int day = 5, int endDay = 5, DateTime? endedAt}) =>
        ShieldSession(
          startAt: at(cairo, 2026, 10, day, sh, sm),
          endAt: at(cairo, 2026, 10, endDay, eh, em),
          endedAt: endedAt,
          reason: ShieldReason.focus,
        );

    test('sums sessions on the day and uses the early end of an ended session', () {
      final s = run(
        inputs(
          shields: [
            shield(10, 0, 10, 25),
            shield(14, 0, 14, 50, endedAt: at(cairo, 2026, 10, 5, 14, 20)),
          ],
        ),
      );
      expect(s.focusMinutes, 45);
    });

    test('overlapping and touching sessions count once', () {
      final s = run(inputs(shields: [shield(10, 0, 11, 0), shield(10, 30, 11, 30), shield(11, 30, 12, 0)]));
      expect(s.focusMinutes, 120);
    });

    test('sessions crossing midnight are clipped to the day', () {
      final s = run(inputs(shields: [shield(23, 30, 0, 30, day: 4), shield(23, 0, 1, 0, endDay: 6)]));
      expect(s.focusMinutes, 30 + 60);
    });

    test("nothing after `at` counts (today's live summary)", () {
      final s = run(inputs(shields: [shield(10, 0, 12, 0)]), atTime: at(cairo, 2026, 10, 5, 10, 40));
      expect(s.focusMinutes, 40);
      expect(DaySummarizer.focusMinutes(const [], from: monday, to: monday), 0);
    });

    test('partial minutes are floored', () {
      final s = run(
        inputs(
          shields: [
            ShieldSession(
              startAt: at(cairo, 2026, 10, 5, 10),
              endAt: at(cairo, 2026, 10, 5, 10).add(const Duration(minutes: 24, seconds: 59)),
              reason: ShieldReason.custom,
            ),
          ],
        ),
      );
      expect(s.focusMinutes, 24);
    });
  });

  group('DST days use real local midnights', () {
    test('spring forward (23 h day): events up to the next local midnight count', () {
      final day = DateTime.utc(2026, 3, 8); // Sunday, a work day
      final s = summarize(
        inputs(
          events: [
            ReminderEvent(
              type: RoutineType.stretch,
              outcome: ReminderOutcome.done,
              at: at(newYork, 2026, 3, 8, 23, 30),
            ),
            ReminderEvent(type: RoutineType.stretch, outcome: ReminderOutcome.done, at: at(newYork, 2026, 3, 9)),
          ],
          shields: [
            ShieldSession(
              startAt: at(newYork, 2026, 3, 7, 23),
              endAt: at(newYork, 2026, 3, 9, 1),
              reason: ShieldReason.untilOff,
            ),
          ],
        ),
        date: day,
        location: newYork,
        at: at(newYork, 2026, 3, 10),
      );
      expect(s.routines[1].done, 1);
      expect(s.focusMinutes, 23 * 60);
    });

    test('fall back (25 h day)', () {
      final day = DateTime.utc(2026, 11); // Sunday 1 November
      final s = summarize(
        inputs(
          events: [
            ReminderEvent(
              type: RoutineType.eyeRest,
              outcome: ReminderOutcome.done,
              at: at(newYork, 2026, 11, 1, 23, 59),
            ),
          ],
          shields: [
            ShieldSession(
              startAt: at(newYork, 2026, 10, 31, 22),
              endAt: at(newYork, 2026, 11, 2, 2),
              reason: ShieldReason.untilOff,
            ),
          ],
        ),
        date: day,
        location: newYork,
        at: at(newYork, 2026, 11, 3),
      );
      expect(s.routines.last.done, 1);
      expect(s.focusMinutes, 25 * 60);
    });
  });
}
