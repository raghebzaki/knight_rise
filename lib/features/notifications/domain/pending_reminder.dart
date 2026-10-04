import 'package:knight_rise/features/notifications/domain/reminder_payload.dart';
import 'package:meta/meta.dart';

/// A notification waiting in the OS scheduler.
@immutable
class PendingReminder {
  const PendingReminder({required this.id, this.payload});

  /// OS notification id.
  final int id;

  /// Decoded payload (fire time + routines); null when absent or unreadable.
  final ReminderPayload? payload;

  @override
  bool operator ==(Object other) => other is PendingReminder && other.id == id && other.payload == payload;

  @override
  int get hashCode => Object.hash(id, payload);

  @override
  String toString() => 'PendingReminder(#$id, $payload)';
}
