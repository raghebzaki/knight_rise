import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/features/quest_log/domain/entities/daily_summary.dart';
import 'package:knight_rise/features/quest_log/domain/services/day_summarizer.dart';
import 'package:knight_rise/features/quest_log/domain/services/streak_calculator.dart';
import 'package:knight_rise/features/quest_log/domain/usecases/history_usecases.dart';
import 'package:knight_rise/features/quest_log/presentation/quest_log_cubit.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:mocktail/mocktail.dart';

import 'fakes.dart';
import 'tz.dart';

class MockMaintainHistory extends Mock implements MaintainHistory;

/// A [QuestLogCubit] over in-memory repositories, in Cairo.
class QuestLogHarness {
  QuestLogHarness({required DateTime now, List<DailySummary> history = const [], List<Routine>? routines})
    : clock = FixedClock(now),
      summaries = FakeDailySummaryRepository(history),
      routines = FakeRoutineRepository(routines ?? Routine.defaults) {
    when(maintain.call).thenAnswer((_) async {});
  }

  final FixedClock clock;
  final FakeDailySummaryRepository summaries;
  final FakeRoutineRepository routines;
  final events = FakeReminderEventRepository();
  final settings = FakeSettingsRepository();
  final schedule = FakeWorkScheduleRepository();
  final shields = FakeShieldRepository();
  final overrides = FakeDayOverrideRepository();
  final location = FakeLocationProvider(cairo);
  final maintain = MockMaintainHistory();

  QuestLogCubit cubit() => QuestLogCubit(
    WatchCycleInputs(routines, schedule, events, settings, shields, overrides),
    summaries,
    const DaySummarizer(),
    const StreakCalculator(),
    CompleteRoutine(events, settings, clock),
    UndoCompletion(events),
    maintain,
    settings,
    clock,
    location,
  );
}

/// A finalized day for [QuestLogHarness] histories: qualified work day
/// unless [qualified] is false, a rest day when [workDay] is false.
DailySummary pastDay(DateTime date, {bool qualified = true, bool workDay = true, int focusMinutes = 0}) => DailySummary(
  date: date,
  isWorkDay: workDay,
  waterMl: 2000,
  waterTargetMl: 2000,
  focusMinutes: focusMinutes,
  thresholdPercent: 70,
  qualified: qualified && workDay,
  finalizedAt: date.add(const Duration(days: 1)),
  routines: [
    for (final r in Routine.defaults)
      RoutineDaySummary(type: r.type, done: r.dailyTarget, target: r.dailyTarget, enabled: true),
  ],
);
