import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';

abstract interface class ReminderEventRepository {
  /// Events with `at >= since`, oldest first. Emits again on every write,
  /// including writes from a background isolate.
  Stream<List<ReminderEvent>> watchSince(DateTime since);

  Future<List<ReminderEvent>> getSince(DateTime since);

  Future<int> add(ReminderEvent event);
}
