import 'package:freezed_annotation/freezed_annotation.dart';

part 'shield_window.freezed.dart';

/// A span during which no reminders fire. `end` is exclusive.
/// Full Shield Mode (sessions, presets, recovery) lands in Milestone 3;
/// the planner already honors these windows.
@freezed
abstract class ShieldWindow with _$ShieldWindow {
  const factory ShieldWindow({required DateTime start, required DateTime end}) = _ShieldWindow;

  const ShieldWindow._();

  bool covers(DateTime t) => !t.isBefore(start) && t.isBefore(end);
}
