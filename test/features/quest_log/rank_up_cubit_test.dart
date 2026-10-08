import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/quest_log/domain/entities/knight_rank.dart';
import 'package:knight_rise/features/quest_log/domain/services/day_summarizer.dart';
import 'package:knight_rise/features/quest_log/domain/services/streak_calculator.dart';
import 'package:knight_rise/features/quest_log/presentation/rank_up_cubit.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';

import '../../helpers/quest_log_harness.dart';
import '../../helpers/tz.dart';

DateTime d(int n) => DateTime.utc(2026, 10, n);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  /// Six qualified work days before Mon 12 Oct (Fri 9 / Sat 10 rest).
  QuestLogHarness sixDays({int hour = 16}) => QuestLogHarness(
    now: at(cairo, 2026, 10, 12, hour),
    history: [
      for (final n in [4, 5, 6, 7, 8, 11]) pastDay(d(n)),
      pastDay(d(9), workDay: false),
      pastDay(d(10), workDay: false),
    ],
  );

  Future<void> qualifyToday(QuestLogHarness h) async {
    for (final r in Routine.defaults) {
      for (var i = 0; i < r.dailyTarget; i++) {
        await h.events.add(
          ReminderEvent(
            type: r.type,
            outcome: ReminderOutcome.done,
            at: at(cairo, 2026, 10, 12, 9),
            waterMl: r.type == RoutineType.hydration ? 250 : null,
          ),
        );
      }
    }
  }

  RankUpCubit cubit(QuestLogHarness h) {
    final c = RankUpCubit(
      WatchCycleInputs(h.routines, h.schedule, h.events, h.settings, h.shields, h.overrides),
      h.summaries,
      const DaySummarizer(),
      const StreakCalculator(),
      h.settings,
      h.clock,
      h.location,
    )..start();
    addTearDown(c.close);
    return c;
  }

  test('the 6-day Squire was celebrated: nothing pending until today lifts it to Knight', () async {
    final h = sixDays();
    await h.settings.markRankCelebrated(d(8)); // Squire was reached on Wed 6 and shown on Thu 8
    final c = cubit(h);
    await settle();
    expect(c.state, isNull);

    await qualifyToday(h);
    await settle();
    expect(c.state, (rank: KnightRank.knight, days: 7));

    await c.markSeen();
    await settle();
    expect(h.settings.current.rankCelebratedOn, d(12));
    expect(c.state, isNull);
  });

  test('a rank reached yesterday (via notifications) is still pending the next morning', () async {
    // Day 7 was finalized for Sun 11; today Mon 12, 08:00, nothing done yet.
    final h = QuestLogHarness(
      now: at(cairo, 2026, 10, 12, 8),
      history: [
        for (final n in [1, 4, 5, 6, 7, 8, 11]) pastDay(d(n)),
        pastDay(d(2), workDay: false),
        pastDay(d(3), workDay: false),
        pastDay(d(9), workDay: false),
        pastDay(d(10), workDay: false),
      ],
    );
    await h.settings.markRankCelebrated(d(5)); // the Squire celebration
    final c = cubit(h);
    await settle();
    expect(c.state, (rank: KnightRank.knight, days: 7));
  });

  test('celebrated on or after the day it was reached: not shown again (restart, next day)', () async {
    final h = sixDays();
    await h.settings.markRankCelebrated(d(12));
    await qualifyToday(h);
    final c = cubit(h);
    await settle();
    expect(c.state, isNull);
  });

  test('a never-celebrated install with an existing rank celebrates it once', () async {
    final h = sixDays(); // Squire reached Wed 6, never celebrated
    final c = cubit(h);
    await settle();
    expect(c.state, (rank: KnightRank.squire, days: 6));
  });

  test('Page is never celebrated', () async {
    final h = QuestLogHarness(now: at(cairo, 2026, 10, 12, 16), history: [pastDay(d(11))]);
    await qualifyToday(h);
    final c = cubit(h);
    await settle();
    expect(c.state, isNull);
  });

  test('refresh on a new day re-watches', () async {
    final h = sixDays();
    await h.settings.markRankCelebrated(d(8));
    final c = cubit(h);
    await settle();
    expect(c.state, isNull);
    await h.summaries.upsert(pastDay(d(12)));
    h.clock.current = at(cairo, 2026, 10, 13, 8);
    c.refresh();
    await settle();
    expect(c.state, (rank: KnightRank.knight, days: 7));
  });
}
