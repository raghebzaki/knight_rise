import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/features/quest_log/domain/entities/daily_summary.dart';
import 'package:knight_rise/features/quest_log/domain/entities/knight_rank.dart';
import 'package:meta/meta.dart';

@immutable
class StreakStatus {
  const StreakStatus({required this.current, required this.best});

  static const none = StreakStatus(current: 0, best: 0);

  /// Qualifying work days in a row up to today.
  final int current;

  /// Longest run ever, including the current one.
  final int best;

  KnightRank get rank => KnightRank.forStreak(current);

  @override
  bool operator ==(Object other) => other is StreakStatus && other.current == current && other.best == best;

  @override
  int get hashCode => Object.hash(current, best);

  @override
  String toString() => 'StreakStatus(current: $current, best: $best)';
}

/// Pure: finalized summaries (+ today's live summary) → streaks.
///
/// Rules (architecture doc 4.4, M4 notes):
/// - a day with [DailySummary.countsTowardStreak] false (rest day, day off,
///   nothing enabled) is neutral: it neither extends nor breaks a run;
/// - a counting day extends the run when qualified and breaks it otherwise;
/// - a date missing between the first and the latest summary breaks the run
///   (the app had no data for it); dates after the latest summary are not
///   finalized yet and are skipped;
/// - today only adds to the run once it already qualifies; an unqualified
///   today never breaks it (the day is not over).
@injectable
class StreakCalculator {
  const StreakCalculator();

  StreakStatus call(List<DailySummary> history, {required DateTime today, DailySummary? todaySummary}) {
    final day0 = dateOnly(today);
    final byDate = {
      for (final s in history)
        if (dateOnly(s.date).isBefore(day0)) dateKey(s.date): s,
    };
    final todayBonus = todaySummary != null && todaySummary.countsTowardStreak && todaySummary.qualified ? 1 : 0;
    if (byDate.isEmpty) return StreakStatus(current: todayBonus, best: todayBonus);

    final dates = byDate.keys.toList()..sort();
    final first = parseDateKey(dates.first);
    final latest = parseDateKey(dates.last);

    // Best run: walk every date from the first summary to the latest.
    var best = 0;
    var run = 0;
    for (var d = first; !d.isAfter(latest); d = addDays(d, 1)) {
      final s = byDate[dateKey(d)];
      if (s == null) {
        run = 0;
      } else if (s.countsTowardStreak) {
        run = s.qualified ? run + 1 : 0;
        if (run > best) best = run;
      }
    }

    // Current run: walk back from yesterday.
    var current = 0;
    for (var d = addDays(day0, -1); !d.isBefore(first); d = addDays(d, -1)) {
      final s = byDate[dateKey(d)];
      if (s == null) {
        if (d.isAfter(latest)) continue; // not finalized yet
        break;
      }
      if (!s.countsTowardStreak) continue;
      if (!s.qualified) break;
      current++;
    }
    current += todayBonus;
    return StreakStatus(current: current, best: current > best ? current : best);
  }
}
