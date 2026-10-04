import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/notifications/data/notification_content.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';

void main() {
  test('single routine copy', () {
    final h = NotificationCopy.build({RoutineType.hydration});
    expect((h.title, h.body), ('Refuel, Knight.', 'One glass of water — 250 ml.'));
    final s = NotificationCopy.build({RoutineType.stretch});
    expect((s.title, s.body), ('Rise and stretch.', '2 minutes: stand up and move.'));
    final e = NotificationCopy.build({RoutineType.eyeRest});
    expect((e.title, e.body), ('Rest your eyes.', 'Look 20 ft away for 20 seconds.'));
  });

  test('merged copy joins labels in routine order', () {
    final m = NotificationCopy.build({RoutineType.eyeRest, RoutineType.hydration});
    expect(m.title, "Knight's call");
    expect(m.body, 'Hydration + Eye rest');
    expect(NotificationCopy.build(RoutineType.values.toSet()).body, 'Hydration + Quick stretch + Eye rest');
  });

  test('channel is that of the lowest-index routine', () {
    expect(NotificationCopy.channelFor({RoutineType.eyeRest, RoutineType.stretch}), 'stretch');
    expect(NotificationCopy.channelFor({RoutineType.eyeRest}), 'eye_rest');
    expect(NotificationCopy.channelFor(RoutineType.values.toSet()), 'hydration');
  });
}
