import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/work_schedule_repository.dart';

@LazySingleton(as: WorkScheduleRepository)
class DriftWorkScheduleRepository implements WorkScheduleRepository {
  const DriftWorkScheduleRepository(this._db);
  final AppDatabase _db;

  @override
  Stream<WorkSchedule> watch() => _db.select(_db.workWindows).watch().map(_toDomain);

  @override
  Future<WorkSchedule> get() => _db.select(_db.workWindows).get().then(_toDomain);

  @override
  Future<void> save(WorkSchedule schedule) => _db.transaction(() async {
    await _db.delete(_db.workWindows).go();
    await _db.batch(
      (b) => b.insertAll(_db.workWindows, [
        for (final MapEntry(key: day, value: windows) in schedule.days.entries)
          for (final w in windows)
            WorkWindowsCompanion.insert(weekday: day, startMinute: w.startMinute, endMinute: w.endMinute),
      ]),
    );
  });

  static WorkSchedule _toDomain(List<WorkWindowRow> rows) {
    final days = <int, List<TimeWindow>>{};
    for (final r in rows) {
      (days[r.weekday] ??= []).add(TimeWindow(startMinute: r.startMinute, endMinute: r.endMinute));
    }
    return WorkSchedule(days: days);
  }
}
