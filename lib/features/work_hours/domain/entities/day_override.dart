import 'package:freezed_annotation/freezed_annotation.dart';

part 'day_override.freezed.dart';

enum DayOverrideKind {
  /// Day off: no work windows that date.
  off,

  /// Working late: the last window ends `extendMinutes` later (capped at 24:00).
  extend,
}

/// Longest "working late" extension per day.
const kMaxExtendMinutes = 240;

/// A one-off change to the work schedule of one local calendar date.
@freezed
abstract class DayOverride with _$DayOverride {
  const factory DayOverride({
    /// Local calendar date; only year/month/day are meaningful (store as
    /// `DateTime.utc(y, m, d)`, see `dateOnly`).
    required DateTime date,
    required DayOverrideKind kind,
    int? extendMinutes,
  }) = _DayOverride;
}
