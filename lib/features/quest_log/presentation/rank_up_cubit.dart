import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/core/time/location_provider.dart';
import 'package:knight_rise/core/utils/combine_latest.dart';
import 'package:knight_rise/features/quest_log/domain/entities/daily_summary.dart';
import 'package:knight_rise/features/quest_log/domain/entities/knight_rank.dart';
import 'package:knight_rise/features/quest_log/domain/repositories/daily_summary_repository.dart';
import 'package:knight_rise/features/quest_log/domain/services/day_summarizer.dart';
import 'package:knight_rise/features/quest_log/domain/services/streak_calculator.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';

/// A rank-up waiting to be celebrated.
typedef PendingRankUp = ({KnightRank rank, int days});

/// App-level watcher for a rank-up that has not been celebrated yet, so the
/// moment shows on whichever tab opens first — including the morning after
/// a streak was completed through notifications. Emits null when nothing is
/// pending; [markSeen] records the celebration (once per rank-up).
@injectable
class RankUpCubit extends Cubit<PendingRankUp?> {
  RankUpCubit(
    this._watchInputs,
    this._summaries,
    this._summarizer,
    this._streaks,
    this._settings,
    this._clock,
    this._location,
  ) : super(null);

  final WatchCycleInputs _watchInputs;
  final DailySummaryRepository _summaries;
  final DaySummarizer _summarizer;
  final StreakCalculator _streaks;
  final SettingsRepository _settings;
  final Clock _clock;
  final LocationProvider _location;

  StreamSubscription<PendingRankUp?>? _sub;
  DateTime? _day;

  void start() {
    unawaited(_sub?.cancel());
    final location = _location.current;
    final day = localDateOf(_clock.now(), location);
    _day = day;
    _sub =
        combineLatest<PendingRankUp?>(
          [_watchInputs(startOfDate(day, location)), _summaries.watchFrom(DateTime.utc(1970))],
          (v) {
            final inputs = v[0]! as CycleInputs;
            final today = _summarizer(SummaryInputs.of(inputs), date: day, location: location, at: _clock.now());
            final streak = _streaks(v[1]! as List<DailySummary>, today: day, todaySummary: today);
            final rank = pendingRankUp(streak, celebratedOn: inputs.settings.rankCelebratedOn);
            return rank == null ? null : (rank: rank, days: streak.current);
          },
        ).listen((pending) {
          if (!isClosed && pending != state) emit(pending);
        });
  }

  /// Re-watches after a resume on a new local day.
  void refresh() {
    if (!isClosed && localDateOf(_clock.now(), _location.current) != _day) start();
  }

  /// Records the celebration (as today), so it is not shown again.
  Future<void> markSeen() => _settings.markRankCelebrated(localDateOf(_clock.now(), _location.current));

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await super.close();
  }
}
