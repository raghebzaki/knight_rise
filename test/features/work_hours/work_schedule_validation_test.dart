import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:knight_rise/features/work_hours/domain/work_schedule_validation.dart';
import 'package:knight_rise/features/work_hours/domain/work_week.dart';

WorkSchedule day(List<TimeWindow> windows, {int weekday = DateTime.monday}) => WorkSchedule(days: {weekday: windows});

void main() {
  group('validateWorkSchedule', () {
    test('standard and empty schedules are valid', () {
      expect(validateWorkSchedule(WorkSchedule.standard()), isEmpty);
      expect(validateWorkSchedule(const WorkSchedule()), isEmpty);
    });

    test('exactly 30 minutes is allowed; 29 is too short', () {
      expect(validateWorkSchedule(day([TimeWindow.hm(9, 0, 9, 30)])), isEmpty);
      expect(validateWorkSchedule(day([TimeWindow.hm(9, 0, 9, 29)])), [
        const WorkScheduleIssue(DateTime.monday, WorkScheduleIssueType.tooShort, 0),
      ]);
    });

    test('touching windows are fine, overlapping ones are flagged on the later window', () {
      expect(validateWorkSchedule(day([TimeWindow.hm(9, 0, 12, 0), TimeWindow.hm(12, 0, 17, 0)])), isEmpty);
      expect(validateWorkSchedule(day([TimeWindow.hm(9, 0, 12, 0), TimeWindow.hm(11, 59, 17, 0)])), [
        const WorkScheduleIssue(DateTime.monday, WorkScheduleIssueType.overlap, 1),
      ]);
    });

    test('unsorted input is judged by start time', () {
      final issues = validateWorkSchedule(day([TimeWindow.hm(13, 0, 17, 0), TimeWindow.hm(9, 0, 14, 0)]));
      expect(issues, [const WorkScheduleIssue(DateTime.monday, WorkScheduleIssueType.overlap, 1)]);
    });

    test('four windows are fine, five are too many', () {
      final four = [for (var h = 8; h < 16; h += 2) TimeWindow.hm(h, 0, h + 1, 0)];
      expect(four, hasLength(4));
      expect(validateWorkSchedule(day(four)), isEmpty);
      final five = [...four, TimeWindow.hm(18, 0, 19, 0)];
      expect(validateWorkSchedule(day(five)), [
        const WorkScheduleIssue(DateTime.monday, WorkScheduleIssueType.tooManyWindows),
      ]);
    });

    test('issues are reported per weekday in weekday order', () {
      final schedule = WorkSchedule(
        days: {
          DateTime.thursday: [TimeWindow.hm(9, 0, 9, 10)],
          DateTime.monday: [TimeWindow.hm(9, 0, 9, 10)],
        },
      );
      expect(validateWorkSchedule(schedule).map((i) => i.weekday), [DateTime.monday, DateTime.thursday]);
    });
  });

  group('work week helpers', () {
    test('week starts on Sunday', () {
      expect(weekdaysSundayFirst.first, DateTime.sunday);
      expect(weekdaysSundayFirst.last, DateTime.saturday);
    });

    test('normalizeSchedule drops empty days and sorts windows', () {
      final n = normalizeSchedule(
        WorkSchedule(
          days: {
            DateTime.monday: [TimeWindow.hm(13, 0, 14, 0), TimeWindow.hm(9, 0, 10, 0)],
            DateTime.friday: const [],
          },
        ),
      );
      expect(n.days.keys, [DateTime.monday]);
      expect(n.days[DateTime.monday]!.first.startMinute, 9 * 60);
    });

    test('uniformSchedule: standard is uniform, mixed is null, empty has no days', () {
      final u = uniformSchedule(WorkSchedule.standard())!;
      expect(u.days, [7, 1, 2, 3, 4]);
      expect(u.windows, [TimeWindow.hm(9, 0, 17, 0)]);
      final mixed = WorkSchedule(
        days: {
          DateTime.sunday: [TimeWindow.hm(9, 0, 17, 0)],
          DateTime.monday: [TimeWindow.hm(10, 0, 17, 0)],
        },
      );
      expect(uniformSchedule(mixed), isNull);
      expect(uniformSchedule(const WorkSchedule())!.days, isEmpty);
    });
  });
}
