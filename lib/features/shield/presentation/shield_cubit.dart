import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/core/time/location_provider.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:knight_rise/features/work_hours/domain/usecases/day_override_usecases.dart';

/// One-shot messages for the UI to show (snackbar), then forget.
enum ShieldMessage {
  /// `Until I turn it off` outside a work window: there is nothing to shield.
  shieldUnavailable,
}

/// Dispatches Shield and today's-override actions from the home screen.
///
/// Holds no display state: the active Shield and today's override are read
/// from the `CycleBloc` snapshot (single source of truth). The cubit has no
/// state of its own; listen to [messages] for one-shot snackbar texts.
@injectable
class ShieldCubit extends Cubit<void> {
  ShieldCubit(
    this._start,
    this._extend,
    this._end,
    this._setDayOff,
    this._extendWorkDay,
    this._clearOverride,
    this._clock,
    this._location,
  ) : super(null);

  final StartShield _start;
  final ExtendShield _extend;
  final EndShield _end;
  final SetDayOff _setDayOff;
  final ExtendWorkDay _extendWorkDay;
  final ClearDayOverride _clearOverride;
  final Clock _clock;
  final LocationProvider _location;

  final _messages = StreamController<ShieldMessage>.broadcast();

  /// One-shot messages (snackbars).
  Stream<ShieldMessage> get messages => _messages.stream;

  void _say(ShieldMessage m) {
    if (!_messages.isClosed) _messages.add(m);
  }

  /// Starts a Shield. Emits [ShieldMessage.shieldUnavailable] when refused.
  Future<void> start(ShieldPreset preset, {Duration? custom}) async {
    final session = await _start(preset, custom: custom);
    if (session == null) _say(ShieldMessage.shieldUnavailable);
  }

  Future<void> extend([Duration extra = const Duration(minutes: 15)]) async {
    await _extend(extra);
  }

  Future<void> end() async {
    await _end();
  }

  /// Today's local calendar date (date-only), per the current zone.
  DateTime get _today => localDateOf(_clock.now(), _location.current);

  Future<void> dayOffToday() async {
    await _setDayOff(_today);
  }

  /// "Working late": adds [minutes] (default 1 h) to today.
  Future<void> workLateToday([int minutes = 60]) async {
    await _extendWorkDay(_today, minutes);
  }

  Future<void> clearToday() => _clearOverride(_today);

  @override
  Future<void> close() async {
    await _messages.close();
    await super.close();
  }
}
