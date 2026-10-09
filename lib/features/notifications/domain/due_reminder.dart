import 'package:flutter/foundation.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';

/// A pending reminder whose fire time has arrived, with its notification id.
@immutable
class DueReminder {
  const DueReminder({required this.id, required this.reminder});

  final int id;
  final PlannedReminder reminder;

  @override
  bool operator ==(Object other) => other is DueReminder && other.id == id && other.reminder == reminder;

  @override
  int get hashCode => Object.hash(id, reminder);

  @override
  String toString() => 'DueReminder($id, $reminder)';
}
