import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/core/time/location_provider.dart';
import 'package:knight_rise/core/utils/combine_latest.dart';
import 'package:knight_rise/features/quest_log/domain/entities/daily_summary.dart';
import 'package:knight_rise/features/quest_log/domain/repositories/daily_summary_repository.dart';
import 'package:knight_rise/features/quest_log/domain/services/day_summarizer.dart';
import 'package:knight_rise/features/quest_log/domain/services/streak_calculator.dart';
import 'package:knight_rise/features/quest_log/domain/usecases/history_usecases.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:timezone/timezone.dart' as tz;

part 'quest_log_cubit.freezed.dart';

/// Days of history kept in [QuestLogView.history] (the 30-day chart).
const kQuestLogHistoryDays = 30;

/// Everything the Quest Log screen renders.
@freezed
abstract class QuestLogView with _$QuestLogView {
  const factory QuestLogView({
    /// Today so far, computed live (never stored).
    required DailySummary today,
    required StreakStatus streak,

    /// Finalized days of the last [kQuestLogHistoryDays], oldest first.
    @Default(<DailySummary>[]) List<DailySummary> history,

    /// Last completion today per routine, in the user's zone.
    @Default(<RoutineType, DateTime>{}) Map<RoutineType, DateTime> lastDoneAt,

    /// Shield minutes over the last 7 days, today included.
    @Default(0) int focusMinutesWeek,
  }) = _QuestLogView;
}

enum QuestLogStatus { loading, ready, failure }

@freezed
abstract class QuestLogState with _$QuestLogState {
  const factory QuestLogState({
    @Default(QuestLogStatus.loading) QuestLogStatus status,
    QuestLogView? view,
    String? error,
  }) = _QuestLogState;
}

/// Quest Log: today's live summary, finalized history, streak and rank.
///
/// Reacts to repository streams only (never to other blocs), so completions
/// from notifications or the break screen show up immediately. Rebuilds at
/// local midnight (and on [refresh] after a resume), finalizing the day that
/// just ended; while a Shield is active it also rebuilds every minute so
/// focus time keeps counting.
@injectable
class QuestLogCubit extends Cubit<QuestLogState> {
  QuestLogCubit(
    this._watchInputs,
    this._summaries,
    this._summarizer,
    this._streaks,
    this._complete,
    this._undo,
    this._maintain,
    this._clock,
    this._location,
  ) : super(const QuestLogState());

  final WatchCycleInputs _watchInputs;
  final DailySummaryRepository _summaries;
  final DaySummarizer _summarizer;
  final StreakCalculator _streaks;
  final CompleteRoutine _complete;
  final UndoCompletion _undo;
  final MaintainHistory _maintain;
  final Clock _clock;
  final LocationProvider _location;

  StreamSubscription<(CycleInputs, List<DailySummary>)>? _sub;
  (CycleInputs, List<DailySummary>)? _latest;
  DateTime? _day;
  Timer? _timer;

  /// Start watching. Call once when the screen opens.
  void start() => _subscribe();

  /// Recompute against the current time (app resumed). Handles a missed
  /// midnight while the app was in the background.
  void refresh() {
    if (isClosed) return;
    if (localDateOf(_clock.now(), _location.current) != _day) {
      unawaited(_rollOver());
    } else {
      _emit();
    }
  }

  /// Logs [ml] of water as a hydration completion; returns the event id for
  /// [undoWater].
  Future<int> logWater(int ml) => _complete(RoutineType.hydration, waterMl: ml);

  Future<void> undoWater(int eventId) => _undo(eventId);

  void _subscribe() {
    unawaited(_sub?.cancel());
    final now = _clock.now();
    final location = _location.current;
    _day = localDateOf(now, location);
    _sub =
        combineLatest<(CycleInputs, List<DailySummary>)>(
          // Every summary: the best streak spans all history (one small row per day).
          [_watchInputs(startOfDate(_day!, location)), _summaries.watchFrom(DateTime.utc(1970))],
          (v) => (v[0]! as CycleInputs, v[1]! as List<DailySummary>),
        ).listen(
          (v) {
            _latest = v;
            _emit();
          },
          onError: (Object e) {
            if (!isClosed) emit(state.copyWith(status: QuestLogStatus.failure, error: e.toString()));
          },
        );
  }

  Future<void> _rollOver() async {
    try {
      await _maintain();
    } on Object catch (e, st) {
      debugPrint('Quest Log rollover maintenance failed: $e\n$st');
    }
    if (!isClosed) _subscribe();
  }

  void _emit() {
    final latest = _latest;
    if (latest == null || isClosed) return;
    final (inputs, summaries) = latest;
    final now = _clock.now();
    final location = _location.current;
    final day = localDateOf(now, location);
    final today = _summarizer(
      SummaryInputs(
        routines: inputs.routines,
        schedule: inputs.schedule,
        settings: inputs.settings,
        events: inputs.todayEvents,
        shields: inputs.shields,
        overrides: inputs.overrides,
      ),
      date: day,
      location: location,
      at: now,
    );
    final historyStart = addDays(day, -kQuestLogHistoryDays);
    final weekStart = addDays(day, -6);
    final history = [
      for (final s in summaries)
        if (!s.date.isBefore(historyStart) && s.date.isBefore(day)) s,
    ];
    emit(
      QuestLogState(
        status: QuestLogStatus.ready,
        view: QuestLogView(
          today: today,
          streak: _streaks(summaries, today: day, todaySummary: today),
          history: history,
          lastDoneAt: {
            for (final MapEntry(:key, :value) in historyFromEvents(inputs.todayEvents).entries)
              if (value.lastDoneAt != null && !value.lastDoneAt!.isBefore(startOfDate(day, location)))
                key: tz.TZDateTime.from(value.lastDoneAt!, location),
          },
          focusMinutesWeek:
              today.focusMinutes +
              history.where((s) => !s.date.isBefore(weekStart)).fold<int>(0, (sum, s) => sum + s.focusMinutes),
        ),
      ),
    );
    _scheduleTimer(now, location, shieldActive: inputs.shields.any((s) => s.isActiveAt(now)));
  }

  void _scheduleTimer(DateTime now, tz.Location location, {required bool shieldActive}) {
    _timer?.cancel();
    final midnight = startOfDate(addDays(_day!, 1), location);
    var delay = midnight.difference(now) + const Duration(milliseconds: 500);
    if (shieldActive && delay > const Duration(minutes: 1)) delay = const Duration(minutes: 1);
    if (delay < const Duration(seconds: 1)) delay = const Duration(seconds: 1);
    _timer = Timer(delay, refresh);
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    await _sub?.cancel();
    await super.close();
  }
}
