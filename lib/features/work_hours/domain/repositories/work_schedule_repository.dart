import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';

abstract interface class WorkScheduleRepository {
  Stream<WorkSchedule> watch();

  Future<WorkSchedule> get();

  Future<void> save(WorkSchedule schedule);
}
