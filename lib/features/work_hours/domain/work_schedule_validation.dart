import 'package:equatable/equatable.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';

/// Limits enforced by [validateWorkSchedule].
abstract final class WorkScheduleLimits {
  static const int minWindowMinutes = 30;
  static const int maxWindowsPerDay = 4;
}

enum WorkScheduleIssueType {
  /// End is not after start (defensive: [TimeWindow] asserts this in debug).
  endNotAfterStart,

  /// Shorter than [WorkScheduleLimits.minWindowMinutes].
  tooShort,

  /// Overlaps the previous window of the same day.
  overlap,

  /// More than [WorkScheduleLimits.maxWindowsPerDay] windows.
  tooManyWindows,
}

/// One validation problem. [windowIndex] indexes the day's windows sorted by
/// start (as [WorkSchedule.windowsFor] returns them); null for day-level issues.
class WorkScheduleIssue extends Equatable {
  const WorkScheduleIssue(this.weekday, this.type, [this.windowIndex]);

  final int weekday;
  final WorkScheduleIssueType type;
  final int? windowIndex;

  @override
  List<Object?> get props => [weekday, type, windowIndex];
}

/// All problems in [schedule], ordered by weekday (1..7) then window.
/// Windows that merely touch (09:00-12:00, 12:00-17:00) are fine.
List<WorkScheduleIssue> validateWorkSchedule(WorkSchedule schedule) {
  final issues = <WorkScheduleIssue>[];
  for (final weekday in schedule.days.keys.toList()..sort()) {
    final windows = schedule.windowsFor(weekday);
    if (windows.length > WorkScheduleLimits.maxWindowsPerDay) {
      issues.add(WorkScheduleIssue(weekday, WorkScheduleIssueType.tooManyWindows));
    }
    for (var i = 0; i < windows.length; i++) {
      final w = windows[i];
      if (w.endMinute <= w.startMinute) {
        issues.add(WorkScheduleIssue(weekday, WorkScheduleIssueType.endNotAfterStart, i));
      } else if (w.durationMinutes < WorkScheduleLimits.minWindowMinutes) {
        issues.add(WorkScheduleIssue(weekday, WorkScheduleIssueType.tooShort, i));
      }
      if (i > 0 && w.startMinute < windows[i - 1].endMinute) {
        issues.add(WorkScheduleIssue(weekday, WorkScheduleIssueType.overlap, i));
      }
    }
  }
  return issues;
}
