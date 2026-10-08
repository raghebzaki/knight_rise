import 'dart:convert';

import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:meta/meta.dart';

/// Data carried inside a scheduled notification so a tap or action can be
/// mapped back to the routines and slot it belongs to, even from a cold
/// background isolate.
///
/// Wire format (version 1): `{"v":1,"t":["hydration","eyeRest"],"at":<epoch ms UTC>}`,
/// plus `"r":1` on a Shield-recovery reminder (omitted otherwise).
@immutable
class ReminderPayload {
  const ReminderPayload({required this.types, required this.fireAt, this.recovery = false});

  factory ReminderPayload.of(PlannedReminder reminder) =>
      ReminderPayload(types: Set.unmodifiable(reminder.types), fireAt: reminder.fireAt, recovery: reminder.recovery);

  static const int version = 1;

  final Set<RoutineType> types;
  final DateTime fireAt;

  /// True for the "Shield down" summary reminder.
  final bool recovery;

  String encode() {
    final sorted = types.toList()..sort((a, b) => a.index.compareTo(b.index));
    return jsonEncode({
      'v': version,
      't': [for (final t in sorted) t.name],
      'at': fireAt.toUtc().millisecondsSinceEpoch,
      if (recovery) 'r': 1,
    });
  }

  /// Decodes [raw]; returns null on any malformed or unsupported input.
  /// Unknown routine names are ignored, but at least one known type must remain.
  static ReminderPayload? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      if (json['v'] != version) return null;
      final names = json['t'];
      final at = json['at'];
      if (names is! List || at is! int) return null;
      final byName = {for (final t in RoutineType.values) t.name: t};
      final types = <RoutineType>{
        for (final n in names)
          if (n is String && byName[n] != null) byName[n]!,
      };
      if (types.isEmpty) return null;
      return ReminderPayload(
        types: Set.unmodifiable(types),
        fireAt: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
        recovery: json['r'] == 1,
      );
    } on Object {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderPayload &&
      other.fireAt.isAtSameMomentAs(fireAt) &&
      other.recovery == recovery &&
      other.types.length == types.length &&
      other.types.containsAll(types);

  @override
  int get hashCode => Object.hash(fireAt.millisecondsSinceEpoch, recovery, Object.hashAllUnordered(types));

  @override
  String toString() =>
      'ReminderPayload(${types.map((t) => t.name).join('+')} @ $fireAt${recovery ? ', recovery' : ''})';
}
