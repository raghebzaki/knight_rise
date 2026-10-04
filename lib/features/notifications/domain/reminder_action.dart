import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:meta/meta.dart';

/// What the user did with a reminder notification.
enum ReminderActionKind { done, snooze, open }

/// A user interaction with a delivered reminder, decoded from the notification
/// payload. Pure Dart so it can cross isolate boundaries into use cases.
@immutable
class ReminderAction {
  const ReminderAction({
    required this.kind,
    required this.types,
    required this.scheduledAt,
    required this.notificationId,
  });

  final ReminderActionKind kind;

  /// Routines covered by the (possibly merged) notification.
  final Set<RoutineType> types;

  /// When the notification was scheduled to fire.
  final DateTime scheduledAt;

  /// OS notification id the action belongs to.
  final int notificationId;

  @override
  bool operator ==(Object other) =>
      other is ReminderAction &&
      other.kind == kind &&
      other.scheduledAt.isAtSameMomentAs(scheduledAt) &&
      other.notificationId == notificationId &&
      other.types.length == types.length &&
      other.types.containsAll(types);

  @override
  int get hashCode =>
      Object.hash(kind, scheduledAt.millisecondsSinceEpoch, notificationId, Object.hashAllUnordered(types));

  @override
  String toString() =>
      'ReminderAction(${kind.name}, ${types.map((t) => t.name).join('+')}, $scheduledAt, #$notificationId)';
}
