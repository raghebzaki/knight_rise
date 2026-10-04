import 'package:freezed_annotation/freezed_annotation.dart';

part 'work_schedule.freezed.dart';

/// A same-day window of local wall-clock time, in minutes since midnight.
/// `end` is exclusive. Windows never cross midnight.
@freezed
abstract class TimeWindow with _$TimeWindow {
  @Assert('startMinute >= 0 && startMinute < 1440', 'start out of range')
  @Assert('endMinute > startMinute && endMinute <= 1440', 'end must be after start')
  const factory TimeWindow({required int startMinute, required int endMinute}) = _TimeWindow;

  const TimeWindow._();

  factory TimeWindow.hm(int startH, int startM, int endH, int endM) =>
      TimeWindow(startMinute: startH * 60 + startM, endMinute: endH * 60 + endM);

  int get durationMinutes => endMinute - startMinute;
}

/// Working hours per ISO weekday (1 = Monday … 7 = Sunday).
/// A weekday with no windows is a day off.
@freezed
abstract class WorkSchedule with _$WorkSchedule {
  const factory WorkSchedule({@Default(<int, List<TimeWindow>>{}) Map<int, List<TimeWindow>> days}) = _WorkSchedule;

  const WorkSchedule._();

  /// Default: Sunday–Thursday, 09:00–17:00; Friday and Saturday off. Editable in Milestone 3.
  factory WorkSchedule.standard() => WorkSchedule(
    days: {
      for (final d in const [DateTime.sunday, DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday])
        d: [TimeWindow.hm(9, 0, 17, 0)],
    },
  );

  /// Windows for [weekday], sorted by start.
  List<TimeWindow> windowsFor(int weekday) {
    final list = [...?days[weekday]]..sort((a, b) => a.startMinute.compareTo(b.startMinute));
    return list;
  }

  bool get isEmpty => days.values.every((w) => w.isEmpty);
}
