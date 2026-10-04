import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';

part 'reminder_event.freezed.dart';

enum ReminderOutcome { scheduled, done, snoozed, missed, dismissed }

/// One thing that happened to a routine: a completion, a snooze, a miss.
@freezed
abstract class ReminderEvent with _$ReminderEvent {
  const factory ReminderEvent({
    required RoutineType type,
    required ReminderOutcome outcome,

    /// When the outcome happened (completion / snooze time).
    required DateTime at,
    int? id,

    /// The reminder slot this event resolves, when known.
    DateTime? scheduledAt,

    /// Set for [ReminderOutcome.snoozed].
    DateTime? snoozedUntil,

    /// Water logged with a hydration completion.
    int? waterMl,
  }) = _ReminderEvent;
}
