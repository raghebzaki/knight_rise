import 'package:freezed_annotation/freezed_annotation.dart';

part 'shield_window.freezed.dart';

/// A span during which no reminders fire. `end` is exclusive.
///
/// [endedAt] is set only when the span was cut short by the user (a manual
/// early end); `end` is then the moment of that early end. The planner uses it
/// to schedule the "Shield down" recovery reminder shortly after the end.
@freezed
abstract class ShieldWindow with _$ShieldWindow {
  const factory ShieldWindow({required DateTime start, required DateTime end, DateTime? endedAt}) = _ShieldWindow;

  const ShieldWindow._();

  bool covers(DateTime t) => !t.isBefore(start) && t.isBefore(end);
}
