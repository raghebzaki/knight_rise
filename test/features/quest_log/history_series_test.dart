import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/quest_log/domain/entities/daily_summary.dart';
import 'package:knight_rise/features/quest_log/domain/services/history_series.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';

DateTime d(int n) => DateTime.utc(2026, 10, n);

/// A finalized day with hydration [waterMl] of 2000 ml, stretch [stretch]/6,
/// eye rest [eyeRest]/12; qualified as given.
DailySummary day(
  int n, {
  int waterMl = 2000,
  int stretch = 6,
  int eyeRest = 12,
  bool workDay = true,
  bool qualified = true,
  bool eyeRestEnabled = true,
  int focus = 0,
  int threshold = 70,
}) => DailySummary(
  date: d(n),
  isWorkDay: workDay,
  waterMl: waterMl,
  waterTargetMl: 2000,
  focusMinutes: focus,
  thresholdPercent: threshold,
  qualified: qualified && workDay,
  finalizedAt: d(n + 1),
  routines: [
    RoutineDaySummary(type: RoutineType.hydration, done: waterMl ~/ 250, target: 8, enabled: true),
    RoutineDaySummary(type: RoutineType.stretch, done: stretch, target: 6, enabled: true),
    RoutineDaySummary(type: RoutineType.eyeRest, done: eyeRest, target: 12, enabled: eyeRestEnabled),
  ],
);

void main() {
  // Today is Wed 14 Oct: the week window is Wed 7 .. Tue 13.
  final today = d(14);

  HistorySeries build(List<DailySummary> s, {HistoryRange range = HistoryRange.week, RoutineType? routine}) =>
      buildHistorySeries(s, today: today, range: range, routine: routine);

  test('the window is the last 7 / 30 days ending yesterday, oldest first', () {
    final week = build(const []);
    expect(week.days.map((x) => x.date), [for (var n = 7; n <= 13; n++) d(n)]);
    expect(week.days.map((x) => x.kind), everyElement(HistoryDayKind.noData));
    expect(week.isEmpty, isTrue);

    final month = build(const [], range: HistoryRange.month);
    expect(month.days, hasLength(30));
    expect(month.days.first.date, DateTime.utc(2026, 9, 14));
    expect(month.days.last.date, d(13));
  });

  test('summaries outside the window (and today) are ignored', () {
    final s = build([day(6), day(14), day(13, stretch: 3, qualified: false)]);
    expect(s.days.where((x) => x.kind != HistoryDayKind.noData).map((x) => x.date), [d(13)]);
    expect(s.stats.workDays, 1);
  });

  group('all routines', () {
    test('uses the overall progress and the qualified flag', () {
      // (2000/2000 + 3/6 + 6/12) / 3 = 66.7 %
      final s = build([day(12, stretch: 3, eyeRest: 6, qualified: false), day(13)]);
      expect(s.days[5].kind, HistoryDayKind.work);
      expect(s.days[5].percent, closeTo(200 / 3, 1e-9));
      expect(s.days[5].goalMet, isFalse);
      expect(s.days[6], HistoryDay(date: d(13), kind: HistoryDayKind.work, percent: 100, goalMet: true));
    });

    test('rest days keep their value but never count', () {
      final s = build([day(9, workDay: false, waterMl: 1000), day(13)]);
      final rest = s.days[2];
      expect(rest.kind, HistoryDayKind.rest);
      expect(rest.percent, closeTo((0.5 + 1 + 1) / 3 * 100, 1e-9));
      expect(rest.goalMet, isFalse);
      expect(s.stats.workDays, 1);
    });

    test('a work day with nothing enabled is "off"', () {
      final none = day(13)
          .copyWith(routines: [for (final r in day(13).routines) r.copyWith(enabled: false)], qualified: false);
      expect(build([none]).days.last, HistoryDay(date: d(13), kind: HistoryDayKind.off));
    });
  });

  group('one routine', () {
    test("hydration is measured in ml against the day's target", () {
      final s = build([day(13, waterMl: 1500)], routine: RoutineType.hydration);
      expect(s.days.last.percent, 75);
      expect(s.days.last.goalMet, isTrue);
    });

    test('goal uses the threshold stored with the day', () {
      final strict = build([day(13, stretch: 4)], routine: RoutineType.stretch);
      expect(strict.days.last.goalMet, isFalse); // 4/6 = 66.7 % < 70 %
      final lenient = build([day(13, stretch: 4, threshold: 60)], routine: RoutineType.stretch);
      expect(lenient.days.last.goalMet, isTrue);
    });

    test('a routine disabled that day is "off" and does not count', () {
      final s = build([day(12, eyeRestEnabled: false), day(13)], routine: RoutineType.eyeRest);
      expect(s.days[5].kind, HistoryDayKind.off);
      expect(s.days[5].percent, isNull);
      expect(s.stats.workDays, 1);
    });

    test('a routine is not met on its own even when the day qualified', () {
      // Day qualified overall at 70 %, but a filter on stretch at 4/6 says below goal.
      final s = build([day(13, stretch: 4)], routine: RoutineType.stretch);
      expect(s.days.last.goalMet, isFalse);
    });
  });

  group('stats', () {
    test('completion rate, goal days, focus and average water', () {
      final s = build([
        day(8, waterMl: 1000, stretch: 3, eyeRest: 6, qualified: false, focus: 25), // 50 %
        day(9, workDay: false, waterMl: 0, focus: 100), // rest: water and rate ignored, focus counted
        day(11), // 100 %
        day(12, focus: 50), // 100 %
      ]);
      expect(
        s.stats,
        const HistoryStats(
          workDays: 3,
          goalDays: 2,
          completionRate: (50 + 100 + 100) / 3,
          focusMinutes: 175,
          averageWaterMl: 1667,
          bestStreak: 2,
        ),
      );
    });

    test('no work days: rate and water are null', () {
      final s = build([day(9, workDay: false), day(10, workDay: false)]);
      expect(s.stats.completionRate, isNull);
      expect(s.stats.averageWaterMl, isNull);
      expect(s.stats.workDays, 0);
      expect(s.isEmpty, isFalse);
    });

    test('best streak counts inside the window only, with rest days neutral', () {
      final s = build([
        day(7),
        day(8, qualified: false),
        day(9, workDay: false),
        day(10, workDay: false),
        day(11),
        day(12),
        day(13),
      ]);
      expect(s.stats.bestStreak, 3);
    });
  });
}
