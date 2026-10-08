import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';

abstract interface class ReminderEventRepository {
  /// Events with `at >= since`, oldest first. Emits again on every write,
  /// including writes from a background isolate.
  Stream<List<ReminderEvent>> watchSince(DateTime since);

  Future<List<ReminderEvent>> getSince(DateTime since);

  Future<int> add(ReminderEvent event);

  /// Removes one event (in-app water undo). No-op when [id] is unknown.
  Future<void> delete(int id);

  /// Removes events with `at < cutoff` (90-day retention); returns the count.
  Future<int> deleteBefore(DateTime cutoff);
}
