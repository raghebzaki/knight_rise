import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/quest_log/domain/entities/knight_rank.dart';
import 'package:knight_rise/features/quest_log/domain/services/streak_calculator.dart';
import 'package:knight_rise/features/quest_log/presentation/quest_log_cubit.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/quest_log_harness.dart';
import '../../helpers/tz.dart';

/// Day [n] of October 2026 (date-only). Monday the 12th is a work day.
DateTime d(int n) => DateTime.utc(2026, 10, n);

Future<QuestLogView> ready(QuestLogCubit cubit) async {
  final s = await cubit.stream.firstWhere((s) => s.status == QuestLogStatus.ready);
  return s.view!;
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('starts loading, then shows today live with streak, rank and last completion', () async {
    // Sun 4 .. Fri 9: Sun–Thu qualified, Fri and Sat rest; today Mon 12 10:00.
    final h = QuestLogHarness(
      now: at(cairo, 2026, 10, 12, 10),
      history: [
        for (final n in [4, 5, 6, 7, 8]) pastDay(d(n)),
        pastDay(d(9), workDay: false),
        pastDay(d(10), workDay: false),
        pastDay(d(11)),
      ],
    );
    await h.events.add(
      ReminderEvent(
        type: RoutineType.hydration,
        outcome: ReminderOutcome.done,
        at: at(cairo, 2026, 10, 12, 9, 15),
        waterMl: 500,
      ),
    );
    final cubit = h.cubit();
    addTearDown(cubit.close);
    expect(cubit.state.status, QuestLogStatus.loading);

    cubit.start();
    final view = await ready(cubit);
    expect(view.today.date, d(12));
    expect(view.today.waterMl, 500);
    expect(view.today.routines.first.done, 1);
    expect(view.streak, StreakStatus(current: 6, best: 6, rankReachedOn: d(6)));
    expect(view.streak.rank, KnightRank.squire);
    expect(view.lastDoneAt.keys, [RoutineType.hydration]);
    expect(view.lastDoneAt[RoutineType.hydration]!.isAtSameMomentAs(at(cairo, 2026, 10, 12, 9, 15)), isTrue);
    expect(view.history.map((s) => s.date.day), [4, 5, 6, 7, 8, 9, 10, 11]);
  });

  test('today extends the streak once it qualifies (e.g. after a background completion)', () async {
    final h = QuestLogHarness(now: at(cairo, 2026, 10, 12, 16), history: [pastDay(d(11))]);
    final cubit = h.cubit()..start();
    addTearDown(cubit.close);
    expect((await ready(cubit)).streak.current, 1);

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
    await settle();
    final view = cubit.state.view!;
    expect(view.today.qualified, isTrue);
    expect(view.streak, const StreakStatus(current: 2, best: 2));
  });

  test('history keeps only the last 30 finalized days; the streak still sees all of them', () async {
    final h = QuestLogHarness(
      now: at(cairo, 2026, 12, 1, 10),
      history: [for (var i = 0; i < 60; i++) pastDay(DateTime.utc(2026, 10, 2 + i))],
    );
    final cubit = h.cubit()..start();
    addTearDown(cubit.close);
    final view = await ready(cubit);
    expect(view.history, hasLength(30));
    expect(view.history.first.date, DateTime.utc(2026, 11));
    expect(view.history.last.date, DateTime.utc(2026, 11, 30));
    expect(view.streak.current, 60);
    expect(view.streak.rank, KnightRank.paladin);
  });

  test('focus minutes: today live plus the last 6 finalized days', () async {
    final h = QuestLogHarness(
      now: at(cairo, 2026, 10, 12, 10, 30),
      history: [
        pastDay(d(5), focusMinutes: 500), // 7 days ago: outside the week
        pastDay(d(6), focusMinutes: 25),
        pastDay(d(11), focusMinutes: 50),
      ],
    );
    await h.shields.add(
      ShieldSession(
        startAt: at(cairo, 2026, 10, 12, 10),
        endAt: at(cairo, 2026, 10, 12, 11),
        reason: ShieldReason.focus,
      ),
    );
    final cubit = h.cubit()..start();
    addTearDown(cubit.close);
    final view = await ready(cubit);
    expect(view.today.focusMinutes, 30); // up to now
    expect(view.focusMinutesWeek, 30 + 25 + 50);
  });

  test('logWater logs a hydration completion with the amount; undoWater removes exactly it', () async {
    final h = QuestLogHarness(now: at(cairo, 2026, 10, 12, 10));
    final cubit = h.cubit()..start();
    addTearDown(cubit.close);
    await ready(cubit);

    final first = await cubit.logWater(500);
    final second = await cubit.logWater(150);
    await settle();
    expect(cubit.state.view!.today.waterMl, 650);
    expect(h.events.all.map((e) => (e.type, e.outcome, e.waterMl)), [
      (RoutineType.hydration, ReminderOutcome.done, 500),
      (RoutineType.hydration, ReminderOutcome.done, 150),
    ]);

    await cubit.undoWater(first);
    await settle();
    expect(h.events.all.map((e) => e.id), [second]);
    expect(cubit.state.view!.today.waterMl, 150);
  });

  test('refresh after midnight finalizes the finished day and moves to the new one', () async {
    final h = QuestLogHarness(now: at(cairo, 2026, 10, 12, 23, 50));
    final cubit = h.cubit()..start();
    addTearDown(cubit.close);
    expect((await ready(cubit)).today.date, d(12));

    cubit.refresh(); // same day: no maintenance
    await settle();
    verifyNever(h.maintain.call);

    h.clock.current = at(cairo, 2026, 10, 13, 0, 5);
    cubit.refresh();
    await pumpEventQueue();
    verify(h.maintain.call).called(1);
    expect(cubit.state.view!.today.date, d(13));
  });

  test('a midnight timer fires the rollover while the screen stays open', () async {
    final h = QuestLogHarness(now: at(cairo, 2026, 10, 12, 23, 59).add(const Duration(seconds: 59)));
    final cubit = h.cubit()..start();
    addTearDown(cubit.close);
    await ready(cubit);
    h.clock.current = at(cairo, 2026, 10, 13).add(const Duration(seconds: 2));
    // The timer is due 1.5 s after "now" (midnight + 500 ms).
    await Future<void>.delayed(const Duration(milliseconds: 1700));
    await pumpEventQueue();
    verify(h.maintain.call).called(1);
    expect(cubit.state.view!.today.date, d(13));
  });

  test('a failed maintenance still moves to the new day', () async {
    final h = QuestLogHarness(now: at(cairo, 2026, 10, 12, 23, 50));
    when(h.maintain.call).thenThrow(StateError('db'));
    final cubit = h.cubit()..start();
    addTearDown(cubit.close);
    await ready(cubit);
    h.clock.current = at(cairo, 2026, 10, 13, 8);
    cubit.refresh();
    await pumpEventQueue();
    expect(cubit.state.view!.today.date, d(13));
  });

  test('a rest day today never adds to the streak', () async {
    // Fri 9 Oct is not a work day.
    final h = QuestLogHarness(now: at(cairo, 2026, 10, 9, 15), history: [pastDay(d(8))]);
    final cubit = h.cubit()..start();
    addTearDown(cubit.close);
    final view = await ready(cubit);
    expect(view.today.countsTowardStreak, isFalse);
    expect(view.streak.current, 1);
  });
}
