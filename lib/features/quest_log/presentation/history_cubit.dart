import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/core/time/location_provider.dart';
import 'package:knight_rise/core/utils/combine_latest.dart';
import 'package:knight_rise/features/quest_log/domain/entities/daily_summary.dart';
import 'package:knight_rise/features/quest_log/domain/repositories/daily_summary_repository.dart';
import 'package:knight_rise/features/quest_log/domain/services/history_series.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/settings/domain/entities/app_settings.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';

part 'history_cubit.freezed.dart';

enum HistoryStatus { loading, ready, failure }

@freezed
abstract class HistoryState with _$HistoryState {
  const factory HistoryState({
    /// Local date the window ends before (date-only).
    required DateTime today,
    @Default(HistoryStatus.loading) HistoryStatus status,
    @Default(HistoryRange.week) HistoryRange range,

    /// Null shows every routine together.
    RoutineType? routine,

    /// Finalized days of the last 30, oldest first.
    @Default(<DailySummary>[]) List<DailySummary> summaries,

    /// The current streak goal, drawn as the threshold line.
    @Default(70) int thresholdPercent,
    @Default(false) bool showTable,
    String? error,
  }) = _HistoryState;

  const HistoryState._();

  /// The finalized summary for [date] (date-only), or null when none exists
  /// (no data yet). Backs the History day detail pane; no extra queries.
  DailySummary? summaryOn(DateTime date) {
    final key = dateKey(date);
    return summaries.where((s) => dateKey(s.date) == key).firstOrNull;
  }

  HistorySeries get series => buildHistorySeries(summaries, today: today, range: range, routine: routine);
}

/// History tab: 7/30-day completion per routine or overall.
///
/// Watches finalized summaries only (finalizing is done by the Quest Log,
/// launch/resume and the background task), and moves its window at local
/// midnight or on [refresh] after a resume.
@injectable
class HistoryCubit extends Cubit<HistoryState> {
  HistoryCubit(this._summaries, this._settings, this._clock, this._location)
    : super(HistoryState(today: localDateOf(_clock.now(), _location.current)));

  final DailySummaryRepository _summaries;
  final SettingsRepository _settings;
  final Clock _clock;
  final LocationProvider _location;

  StreamSubscription<(List<DailySummary>, AppSettings)>? _sub;
  Timer? _midnight;

  void start() => _subscribe();

  void refresh() {
    if (isClosed) return;
    if (localDateOf(_clock.now(), _location.current) != state.today) _subscribe();
  }

  void setRange(HistoryRange range) => emit(state.copyWith(range: range));

  void setRoutine(RoutineType? routine) => emit(state.copyWith(routine: routine));

  void toggleTable() => emit(state.copyWith(showTable: !state.showTable));

  void _subscribe() {
    unawaited(_sub?.cancel());
    final now = _clock.now();
    final location = _location.current;
    final today = localDateOf(now, location);
    if (today != state.today) emit(state.copyWith(today: today));
    _sub =
        combineLatest<(List<DailySummary>, AppSettings)>([
          _summaries.watchFrom(addDays(today, -HistoryRange.month.days)),
          _settings.watch(),
        ], (v) => (v[0]! as List<DailySummary>, v[1]! as AppSettings)).listen(
          (v) {
            if (isClosed) return;
            emit(
              state.copyWith(
                status: HistoryStatus.ready,
                summaries: v.$1,
                thresholdPercent: v.$2.streakThresholdPercent,
                error: null,
              ),
            );
          },
          onError: (Object e) {
            if (!isClosed) emit(state.copyWith(status: HistoryStatus.failure, error: e.toString()));
          },
        );
    _midnight?.cancel();
    final delay = startOfDate(addDays(today, 1), location).difference(now) + const Duration(milliseconds: 500);
    _midnight = Timer(delay < const Duration(seconds: 1) ? const Duration(seconds: 1) : delay, refresh);
  }

  @override
  Future<void> close() async {
    _midnight?.cancel();
    await _sub?.cancel();
    await super.close();
  }
}
