import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/quest_log/domain/entities/daily_summary.dart';
import 'package:knight_rise/features/quest_log/domain/entities/knight_rank.dart';
import 'package:knight_rise/features/quest_log/domain/services/streak_calculator.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';

/// Day [n] of October 2026.
DateTime d(int n) => DateTime.utc(2026, 10, n);

/// Q = qualified work day, x = unqualified work day, r = rest day,
/// n = work day with nothing enabled.
DailySummary day(int n, String kind) => DailySummary(
  date: d(n),
  isWorkDay: kind != 'r',
  waterMl: 0,
  waterTargetMl: 2000,
  focusMinutes: 0,
  thresholdPercent: 70,
  qualified: kind == 'Q',
  finalizedAt: d(n + 1),
  routines: [RoutineDaySummary(type: RoutineType.stretch, done: 0, target: 6, enabled: kind != 'n')],
);

/// Summaries for consecutive days starting at the 1st, from a pattern
/// such as 'QQrQx'.
List<DailySummary> days(String pattern, {int start = 1}) => [
  for (var i = 0; i < pattern.length; i++) day(start + i, pattern[i]),
];

void main() {
  const calc = StreakCalculator();

  StreakStatus run(List<DailySummary> h, {required int today, DailySummary? todaySummary}) =>
      calc(h, today: d(today), todaySummary: todaySummary);

  test('no history is a zero streak, Page rank', () {
    final s = run(const [], today: 5);
    expect(s, StreakStatus.none);
    expect(s.rank, KnightRank.page);
  });

  test('consecutive qualified days up to yesterday', () {
    expect(run(days('QQQ'), today: 4), StreakStatus(current: 3, best: 3, rankReachedOn: d(3)));
  });

  test('an unqualified work day breaks the run', () {
    expect(run(days('QQQxQQ'), today: 7), const StreakStatus(current: 2, best: 3));
    expect(run(days('QQx'), today: 4), const StreakStatus(current: 0, best: 2));
  });

  test('rest days are neutral: they neither extend nor break', () {
    // Thu Q, Fri rest, Sat rest, Sun Q, Mon Q.
    expect(run(days('QrrQQ'), today: 6), StreakStatus(current: 3, best: 3, rankReachedOn: d(5)));
    expect(run(days('Qrr'), today: 4), const StreakStatus(current: 1, best: 1));
    expect(run(days('rrr'), today: 4), StreakStatus.none);
  });

  test('a work day with nothing enabled is neutral too', () {
    expect(run(days('QnQ'), today: 4), const StreakStatus(current: 2, best: 2));
  });

  test('today adds one only once it qualifies, and never breaks the run', () {
    final h = days('QQ');
    expect(run(h, today: 3, todaySummary: day(3, 'Q')).current, 3);
    expect(run(h, today: 3, todaySummary: day(3, 'x')).current, 2);
    expect(run(h, today: 3, todaySummary: day(3, 'r')).current, 2);
    expect(run(h, today: 3).current, 2);
    expect(run(const [], today: 3, todaySummary: day(3, 'Q')), const StreakStatus(current: 1, best: 1));
  });

  test('best includes today when the current run is the longest', () {
    expect(
      run(days('QQ'), today: 3, todaySummary: day(3, 'Q')),
      StreakStatus(current: 3, best: 3, rankReachedOn: d(3)),
    );
  });

  test('a missing date inside the history breaks the run (no data for it)', () {
    final h = [...days('QQQ'), ...days('QQ', start: 5)]; // the 4th is missing
    expect(run(h, today: 7), const StreakStatus(current: 2, best: 3));
  });

  test('dates after the latest summary are pending (not finalized yet) and skipped', () {
    // Summaries up to the 3rd, today is the 6th: the 4th and 5th are not
    // finalized yet (e.g. right after midnight) and must not zero the streak.
    expect(run(days('QQQ'), today: 6), StreakStatus(current: 3, best: 3, rankReachedOn: d(3)));
  });

  test('summaries dated today or later are ignored (today comes from todaySummary)', () {
    final h = [...days('QQ'), day(3, 'x'), day(4, 'x')];
    expect(run(h, today: 3), const StreakStatus(current: 2, best: 2));
  });

  test('input order does not matter', () {
    expect(run(days('QQxQ').reversed.toList(), today: 5), const StreakStatus(current: 1, best: 2));
  });

  test('rank follows the current streak, not the best', () {
    final h = [...days('Q' * 10), day(11, 'x'), ...days('QQQ', start: 12)];
    final s = run(h, today: 15);
    expect(s, StreakStatus(current: 3, best: 10, rankReachedOn: d(14)));
    expect(s.rank, KnightRank.squire);
  });

  test('a 30-day run across weekends reaches Paladin', () {
    // Sun–Thu work, Fri–Sat rest, for 6 weeks starting Sunday the 4th.
    final pattern = 'QQQQQrr' * 6;
    final s = run(days(pattern, start: 4), today: 4 + pattern.length);
    expect(s.current, 30);
    expect(s.rank, KnightRank.paladin);
  });

  group('rankReachedOn', () {
    test('is the minDays-th qualifying day of the current run, rest days skipped', () {
      // Q Q r r Q Q Q Q Q: qualifying 1,2,5,6,7,8,9 → Knight (7) reached on the 9th.
      final s = run(days('QQrrQQQQQ'), today: 10);
      expect(s.rank, KnightRank.knight);
      expect(s.rankReachedOn, d(9));
    });

    test('today counts once it qualifies', () {
      final s = run(days('QQ'), today: 3, todaySummary: day(3, 'Q'));
      expect(s.rankReachedOn, d(3));
    });

    test('Page has none', () {
      expect(run(days('QQ'), today: 3).rankReachedOn, isNull);
      expect(StreakStatus.none.rankReachedOn, isNull);
    });
  });

  group('pendingRankUp', () {
    final squireOn5 = StreakStatus(current: 4, best: 4, rankReachedOn: d(5));

    test('pending until celebrated on or after the day it was reached', () {
      expect(pendingRankUp(squireOn5), KnightRank.squire);
      expect(pendingRankUp(squireOn5, celebratedOn: d(4)), KnightRank.squire);
      expect(pendingRankUp(squireOn5, celebratedOn: d(5)), isNull);
      expect(pendingRankUp(squireOn5, celebratedOn: DateTime(2026, 10, 6, 9)), isNull);
    });

    test('nothing for Page', () {
      expect(pendingRankUp(StreakStatus.none), isNull);
    });
  });
}
