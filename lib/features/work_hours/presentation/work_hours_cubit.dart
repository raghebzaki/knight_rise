import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/work_schedule_repository.dart';
import 'package:knight_rise/features/work_hours/domain/work_schedule_validation.dart';
import 'package:knight_rise/features/work_hours/domain/work_week.dart';

/// Editable draft of the weekly schedule.
///
/// `windows` holds every weekday, including off days, so switching a day off
/// and on again restores its windows; only `enabled` days reach `schedule`.
class WorkHoursState extends Equatable {
  const WorkHoursState({
    this.loaded = false,
    this.windows = const {},
    this.enabled = const {},
    this.saved = const WorkSchedule(),
    this.saving = false,
  });

  final bool loaded;
  final Map<int, List<TimeWindow>> windows;
  final Set<int> enabled;

  /// Normalized schedule as last persisted.
  final WorkSchedule saved;
  final bool saving;

  List<TimeWindow> windowsOf(int weekday) => windows[weekday] ?? const [];

  /// What Save would persist: enabled days only, normalized.
  WorkSchedule get schedule => normalizeSchedule(WorkSchedule(days: {for (final d in enabled) d: windowsOf(d)}));

  List<WorkScheduleIssue> get issues => validateWorkSchedule(schedule);

  List<WorkScheduleIssue> issuesFor(int weekday) => [
    if (enabled.contains(weekday)) ...issues.where((i) => i.weekday == weekday),
  ];

  bool get isValid => issues.isEmpty;
  bool get isDirty => schedule != saved;
  bool get canSave => loaded && !saving && isDirty && isValid;

  /// True when `addWindow` has room: under the window cap and the default
  /// window fits before midnight.
  bool canAddWindow(int weekday) => _nextWindow(windowsOf(weekday)) != null;

  WorkHoursState copyWith({
    bool? loaded,
    Map<int, List<TimeWindow>>? windows,
    Set<int>? enabled,
    WorkSchedule? saved,
    bool? saving,
  }) => WorkHoursState(
    loaded: loaded ?? this.loaded,
    windows: windows ?? this.windows,
    enabled: enabled ?? this.enabled,
    saved: saved ?? this.saved,
    saving: saving ?? this.saving,
  );

  @override
  List<Object?> get props => [loaded, windows, enabled, saved, saving];
}

TimeWindow? _nextWindow(List<TimeWindow> existing) {
  if (existing.length >= WorkScheduleLimits.maxWindowsPerDay) return null;
  if (existing.isEmpty) return TimeWindow.hm(9, 0, 17, 0);
  final lastEnd = existing.map((w) => w.endMinute).reduce((a, b) => a > b ? a : b);
  final start = lastEnd + 60;
  final end = start + 60;
  return end <= 1440 ? TimeWindow(startMinute: start, endMinute: end) : null;
}

@injectable
class WorkHoursCubit extends Cubit<WorkHoursState> {
  WorkHoursCubit(this._repo) : super(const WorkHoursState());

  final WorkScheduleRepository _repo;

  static const _presetWindow = TimeWindow(startMinute: 9 * 60, endMinute: 17 * 60);

  Future<void> load() async {
    final saved = normalizeSchedule(await _repo.get());
    if (isClosed) return;
    emit(
      WorkHoursState(
        loaded: true,
        saved: saved,
        enabled: saved.days.keys.toSet(),
        windows: {for (final d in weekdaysSundayFirst) d: saved.windowsFor(d)},
      ),
    );
  }

  void setDayEnabled(int weekday, {required bool enabled}) {
    final on = {...state.enabled};
    var windows = state.windows;
    if (enabled) {
      on.add(weekday);
      if (state.windowsOf(weekday).isEmpty) {
        windows = {
          ...windows,
          weekday: [_presetWindow],
        };
      }
    } else {
      on.remove(weekday);
    }
    emit(state.copyWith(enabled: on, windows: windows));
  }

  /// Appends the default next window; false when it does not fit.
  bool addWindow(int weekday) {
    final next = _nextWindow(state.windowsOf(weekday));
    if (next == null) return false;
    _setWindows(weekday, [...state.windowsOf(weekday), next]);
    return true;
  }

  /// Replaces the window at `index`; false (and no change) when the range is
  /// invalid.
  bool updateWindow(int weekday, int index, int startMinute, int endMinute) {
    final list = [...state.windowsOf(weekday)];
    if (index < 0 || index >= list.length) return false;
    if (startMinute < 0 || startMinute >= 1440 || endMinute <= startMinute || endMinute > 1440) return false;
    list[index] = TimeWindow(startMinute: startMinute, endMinute: endMinute);
    _setWindows(weekday, list);
    return true;
  }

  void removeWindow(int weekday, int index) {
    final list = [...state.windowsOf(weekday)];
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    _setWindows(weekday, list);
  }

  /// Copies Sunday's windows to every other day that is on. No-op when
  /// Sunday is off.
  void copySundayToWorkDays() {
    if (!state.enabled.contains(DateTime.sunday)) return;
    final sunday = state.windowsOf(DateTime.sunday);
    emit(
      state.copyWith(
        windows: {
          for (final d in weekdaysSundayFirst)
            d: d != DateTime.sunday && state.enabled.contains(d) ? sunday : state.windowsOf(d),
        },
      ),
    );
  }

  /// Sun-Thu 09:00-17:00; Friday and Saturday off.
  void applySunThu() =>
      _applyPreset(const [DateTime.sunday, DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday]);

  /// Mon-Fri 09:00-17:00; Saturday and Sunday off.
  void applyMonFri() =>
      _applyPreset(const [DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday, DateTime.friday]);

  void _applyPreset(List<int> days) => emit(
    state.copyWith(
      enabled: days.toSet(),
      windows: {
        for (final d in weekdaysSundayFirst) d: days.contains(d) ? const [_presetWindow] : state.windowsOf(d),
      },
    ),
  );

  void _setWindows(int weekday, List<TimeWindow> list) {
    list.sort((a, b) => a.startMinute.compareTo(b.startMinute));
    emit(state.copyWith(windows: {...state.windows, weekday: list}));
  }

  /// Persists the draft when valid and changed; true on success.
  Future<bool> save() async {
    if (!state.canSave) return false;
    final schedule = state.schedule;
    emit(state.copyWith(saving: true));
    try {
      await _repo.save(schedule);
    } on Object {
      if (!isClosed) emit(state.copyWith(saving: false));
      rethrow;
    }
    if (!isClosed) emit(state.copyWith(saving: false, saved: schedule));
    return true;
  }
}
