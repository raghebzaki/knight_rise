import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/notifications/domain/reminder_payload.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';

void main() {
  final at = DateTime.utc(2026, 10, 5, 7, 30);

  test('encodes the documented wire format', () {
    final p = ReminderPayload(types: const {RoutineType.eyeRest, RoutineType.hydration}, fireAt: at);
    expect(jsonDecode(p.encode()), {
      'v': 1,
      't': ['hydration', 'eyeRest'],
      'at': at.millisecondsSinceEpoch,
    });
  });

  test('round-trips, and of() copies a PlannedReminder', () {
    final p = ReminderPayload.of(PlannedReminder(fireAt: at, types: const {RoutineType.stretch, RoutineType.eyeRest}));
    final back = ReminderPayload.tryDecode(p.encode());
    expect(back, p);
    expect(back!.fireAt.isAtSameMomentAs(at), isTrue);
  });

  test('returns null for malformed input', () {
    for (final raw in [
      null,
      '',
      'not json',
      '[]',
      '"x"',
      '{}',
      '{"v":2,"t":["hydration"],"at":1}',
      '{"t":["hydration"],"at":1}',
      '{"v":1,"at":1}',
      '{"v":1,"t":["hydration"]}',
      '{"v":1,"t":"hydration","at":1}',
      '{"v":1,"t":["hydration"],"at":"1"}',
      '{"v":1,"t":[],"at":1}',
      '{"v":1,"t":["nope",3],"at":1}',
    ]) {
      expect(ReminderPayload.tryDecode(raw), isNull, reason: '$raw');
    }
  });

  test('ignores unknown routine names but keeps known ones', () {
    final p = ReminderPayload.tryDecode('{"v":1,"t":["nope","stretch"],"at":1000}');
    expect(p!.types, {RoutineType.stretch});
  });
}
