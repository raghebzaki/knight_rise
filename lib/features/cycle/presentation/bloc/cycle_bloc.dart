import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/cycle_snapshot.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:timezone/timezone.dart' as tz;

part 'cycle_bloc.freezed.dart';

// ---------------------------------------------------------------- events

sealed class CycleEvent {
  const CycleEvent();
}

/// Start watching persisted state. Dispatch once when the dashboard opens.
final class CycleStarted extends CycleEvent {
  const CycleStarted();
}

/// Recompute against the current time (app resumed, timer fired).
final class CycleRefreshRequested extends CycleEvent {
  const CycleRefreshRequested();
}

final class RoutineCompleted extends CycleEvent {
  const RoutineCompleted(this.type, {this.waterMl});
  final RoutineType type;

  /// Hydration only: amount to log instead of the default per-tap amount.
  final int? waterMl;
}

final class RoutineSnoozed extends CycleEvent {
  const RoutineSnoozed(this.type);
  final RoutineType type;
}

final class _InputsChanged extends CycleEvent {
  const _InputsChanged(this.inputs);
  final CycleInputs inputs;
}

final class _InputsFailed extends CycleEvent {
  const _InputsFailed(this.error);
  final Object error;
}

// ----------------------------------------------------------------- state

enum CycleStatus { loading, ready, failure }

@freezed
abstract class CycleState with _$CycleState {
  const factory CycleState({@Default(CycleStatus.loading) CycleStatus status, CycleSnapshot? snapshot, String? error}) =
      _CycleState;
}

// ------------------------------------------------------------------ bloc

/// The break-cycle engine for the UI.
///
/// Truth lives in the database (and, from Milestone 2, in the OS
/// notification schedule). This bloc only derives a [CycleSnapshot] from
/// persisted inputs + the clock, and re-derives it exactly when something
/// can change (next slot, snooze expiry, window edge, midnight). Countdown
/// seconds are rendered by the widget, not stored here.
@injectable
class CycleBloc extends Bloc<CycleEvent, CycleState> {
  CycleBloc(this._watchInputs, this._buildSnapshot, this._complete, this._snooze, this._clock, this._location)
    : super(const CycleState()) {
    on<CycleStarted>((_, _) => _subscribe());
    on<_InputsChanged>((e, emit) {
      _inputs = e.inputs;
      _emitSnapshot(emit);
    });
    on<_InputsFailed>((e, emit) => emit(state.copyWith(status: CycleStatus.failure, error: e.error.toString())));
    on<CycleRefreshRequested>((_, emit) {
      if (startOfLocalDay(_clock.now(), _location) != _day) _subscribe();
      _emitSnapshot(emit);
    });
    on<RoutineCompleted>((e, _) => _complete(e.type, waterMl: e.waterMl));
    on<RoutineSnoozed>((e, _) => _snooze(e.type));
  }

  final WatchCycleInputs _watchInputs;
  final BuildCycleSnapshot _buildSnapshot;
  final CompleteRoutine _complete;
  final SnoozeRoutine _snooze;
  final Clock _clock;
  final tz.Location _location;

  StreamSubscription<CycleInputs>? _sub;
  Timer? _refresh;
  CycleInputs? _inputs;
  DateTime? _day;

  /// Upper bound between refreshes, so a sleeping device or a changed
  /// system clock can never leave the dashboard stale for long.
  static const _maxRefreshGap = Duration(minutes: 15);

  void _subscribe() {
    unawaited(_sub?.cancel());
    _day = startOfLocalDay(_clock.now(), _location);
    _sub = _watchInputs(_day!).listen((i) => add(_InputsChanged(i)), onError: (Object e) => add(_InputsFailed(e)));
  }

  void _emitSnapshot(Emitter<CycleState> emit) {
    final inputs = _inputs;
    if (inputs == null) return;
    final now = _clock.now();
    final snapshot = _buildSnapshot(inputs, now: now, location: _location);
    emit(CycleState(status: CycleStatus.ready, snapshot: snapshot));
    _scheduleRefresh(snapshot.nextChangeAt.difference(now));
  }

  void _scheduleRefresh(Duration untilChange) {
    _refresh?.cancel();
    var delay = untilChange + const Duration(milliseconds: 500);
    if (delay > _maxRefreshGap) delay = _maxRefreshGap;
    if (delay < const Duration(seconds: 1)) delay = const Duration(seconds: 1);
    _refresh = Timer(delay, () {
      if (!isClosed) add(const CycleRefreshRequested());
    });
  }

  @override
  Future<void> close() async {
    _refresh?.cancel();
    await _sub?.cancel();
    await super.close();
  }
}
