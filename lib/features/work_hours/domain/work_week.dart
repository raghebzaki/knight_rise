import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';

/// ISO weekdays in display order. The week starts on Sunday in this app.
const List<int> weekdaysSundayFirst = [
  DateTime.sunday,
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
  DateTime.saturday,
];

/// [schedule] with empty days dropped and windows sorted; two schedules that
/// mean the same thing normalize to equal values.
WorkSchedule normalizeSchedule(WorkSchedule schedule) => WorkSchedule(
  days: {
    for (final d in schedule.days.keys)
      if (schedule.windowsFor(d).isNotEmpty) d: schedule.windowsFor(d),
  },
);

/// The work days (Sunday-first) and windows when every work day has the same
/// windows; null for a mixed ("custom") schedule. No work days gives an empty
/// day list.
({List<int> days, List<TimeWindow> windows})? uniformSchedule(WorkSchedule schedule) {
  final days = [
    for (final d in weekdaysSundayFirst)
      if (schedule.windowsFor(d).isNotEmpty) d,
  ];
  if (days.isEmpty) return (days: const [], windows: const []);
  final first = schedule.windowsFor(days.first);
  final same = days.every((d) => _sameWindows(schedule.windowsFor(d), first));
  return same ? (days: days, windows: first) : null;
}

bool _sameWindows(List<TimeWindow> a, List<TimeWindow> b) =>
    a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((e) => e);
