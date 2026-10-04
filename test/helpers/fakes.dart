import 'dart:async';

import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/routines/domain/repositories/routine_repository.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/scheduler/domain/repositories/reminder_event_repository.dart';
import 'package:knight_rise/features/settings/domain/entities/app_settings.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/work_schedule_repository.dart';

/// In-memory repositories that behave like the Drift ones: every watch()
/// emits the current value immediately and again after each write.
class _Cell<T> {
  _Cell(this.value);
  T value;
  final _changes = StreamController<void>.broadcast();

  Stream<R> watch<R>(R Function(T) map) {
    late StreamController<R> controller;
    StreamSubscription<void>? sub;
    controller = StreamController<R>(
      onListen: () {
        controller.add(map(value));
        sub = _changes.stream.listen((_) => controller.add(map(value)));
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  void set(T v) {
    value = v;
    _changes.add(null);
  }
}

class FakeRoutineRepository implements RoutineRepository {
  FakeRoutineRepository([List<Routine> initial = Routine.defaults]) : _cell = _Cell([...initial]);
  final _Cell<List<Routine>> _cell;

  @override
  Stream<List<Routine>> watchAll() => _cell.watch((v) => v);

  @override
  Future<List<Routine>> getAll() async => _cell.value;

  @override
  Future<void> save(Routine routine) async => _cell.set([
    for (final r in _cell.value)
      if (r.type == routine.type) routine else r,
  ]);
}

class FakeWorkScheduleRepository implements WorkScheduleRepository {
  FakeWorkScheduleRepository([WorkSchedule? initial]) : _cell = _Cell(initial ?? WorkSchedule.standard());
  final _Cell<WorkSchedule> _cell;

  @override
  Stream<WorkSchedule> watch() => _cell.watch((v) => v);

  @override
  Future<WorkSchedule> get() async => _cell.value;

  @override
  Future<void> save(WorkSchedule schedule) async => _cell.set(schedule);
}

class FakeReminderEventRepository implements ReminderEventRepository {
  final _cell = _Cell<List<ReminderEvent>>([]);
  List<ReminderEvent> get all => _cell.value;

  List<ReminderEvent> _since(DateTime since) => _cell.value.where((e) => !e.at.isBefore(since)).toList();

  @override
  Stream<List<ReminderEvent>> watchSince(DateTime since) => _cell.watch((_) => _since(since));

  @override
  Future<List<ReminderEvent>> getSince(DateTime since) async => _since(since);

  @override
  Future<int> add(ReminderEvent event) async {
    final id = _cell.value.length + 1;
    _cell.set([..._cell.value, event.copyWith(id: id)]);
    return id;
  }
}

class FakeSettingsRepository implements SettingsRepository {
  final _cell = _Cell<AppSettings>(const AppSettings());

  @override
  Stream<AppSettings> watch() => _cell.watch((v) => v);

  @override
  Future<AppSettings> get() async => _cell.value;

  @override
  Future<void> save(AppSettings settings) async => _cell.set(settings);
}
