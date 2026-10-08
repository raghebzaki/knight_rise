import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_window.dart';

part 'shield_session.freezed.dart';

/// Why a Shield was raised. Stored by `name`.
enum ShieldReason { focus, meeting, untilOff, custom }

/// A stored Shield (focus / meeting) session.
@freezed
abstract class ShieldSession with _$ShieldSession {
  const factory ShieldSession({
    required DateTime startAt,
    required DateTime endAt,
    required ShieldReason reason,
    int? id,

    /// Set when the user ended the Shield before [endAt].
    DateTime? endedAt,
  }) = _ShieldSession;

  const ShieldSession._();

  /// The moment the Shield stops applying: [endedAt] if earlier than [endAt].
  DateTime get effectiveEnd {
    final e = endedAt;
    return e != null && e.isBefore(endAt) ? e : endAt;
  }

  /// True when the user ended this session before its planned end.
  bool get endedEarly => endedAt != null && endedAt!.isBefore(endAt);

  /// `startAt <= t < effectiveEnd`.
  bool isActiveAt(DateTime t) => !t.isBefore(startAt) && t.isBefore(effectiveEnd);

  /// Window the planner suppresses reminders in.
  ShieldWindow toWindow() => ShieldWindow(start: startAt, end: effectiveEnd, endedAt: endedEarly ? endedAt : null);
}
