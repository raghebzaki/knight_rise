import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/notifications/presentation/notification_permission_cubit.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';

import '../../helpers/fakes.dart';

const _unknown = NotificationPermissionState(NotificationPermissionStatus.unknown);
const _enabled = NotificationPermissionState(NotificationPermissionStatus.enabled);
const _disabled = NotificationPermissionState(NotificationPermissionStatus.disabled);
const _denied = NotificationPermissionState(NotificationPermissionStatus.disabled, requestDenied: true);
const _dismissed = NotificationPermissionState(NotificationPermissionStatus.dismissed);

void main() {
  late FakeNotificationGateway gateway;
  late FakeScheduleReconciler reconciler;

  NotificationPermissionCubit build() => NotificationPermissionCubit(gateway, reconciler);

  setUp(() {
    gateway = FakeNotificationGateway();
    reconciler = FakeScheduleReconciler();
  });

  test('starts unknown and does not show the prompt', () {
    final cubit = build();
    expect(cubit.state, _unknown);
    expect(cubit.state.showPrompt, isFalse);
    addTearDown(cubit.close);
  });

  blocTest<NotificationPermissionCubit, NotificationPermissionState>(
    'check: enabled',
    build: build,
    act: (c) => c.check(),
    expect: () => [_enabled],
    verify: (_) => expect(gateway.requestPermissionCalls, 0, reason: 'check never prompts'),
  );

  blocTest<NotificationPermissionCubit, NotificationPermissionState>(
    'check: disabled shows the prompt, without opening the system dialog',
    setUp: () => gateway.enabled = false,
    build: build,
    act: (c) => c.check(),
    expect: () => [_disabled],
    verify: (c) {
      expect(c.state.showPrompt, isTrue);
      expect(gateway.requestPermissionCalls, 0);
    },
  );

  blocTest<NotificationPermissionCubit, NotificationPermissionState>(
    'request: granted -> enabled and a manual reconcile',
    setUp: () => gateway
      ..enabled = false
      ..grantOnRequest = true,
    build: build,
    seed: () => _disabled,
    act: (c) => c.request(),
    expect: () => [_enabled],
    verify: (_) {
      expect(gateway.requestPermissionCalls, 1);
      expect(reconciler.calls, [ReconcileTrigger.manual]);
    },
  );

  blocTest<NotificationPermissionCubit, NotificationPermissionState>(
    'request: refused -> stays disabled, flagged as denied, no reconcile',
    setUp: () => gateway
      ..enabled = false
      ..grantOnRequest = false,
    build: build,
    seed: () => _disabled,
    act: (c) => c.request(),
    expect: () => [_denied],
    verify: (_) => expect(reconciler.calls, isEmpty),
  );

  blocTest<NotificationPermissionCubit, NotificationPermissionState>(
    'a later check keeps the denied flag; enabling in system settings clears the prompt',
    setUp: () => gateway.enabled = false,
    build: build,
    seed: () => _denied,
    act: (c) async {
      await c.check();
      gateway.enabled = true;
      await c.check();
    },
    expect: () => [_enabled],
    verify: (c) => expect(c.state.requestDenied, isFalse),
  );

  blocTest<NotificationPermissionCubit, NotificationPermissionState>(
    'request when already enabled does not reconcile again',
    build: build,
    seed: () => _enabled,
    act: (c) => c.request(),
    expect: () => <NotificationPermissionState>[],
    verify: (_) => expect(reconciler.calls, isEmpty),
  );

  blocTest<NotificationPermissionCubit, NotificationPermissionState>(
    'dismiss hides the prompt and a resume check does not bring it back',
    setUp: () => gateway.enabled = false,
    build: build,
    seed: () => _disabled,
    act: (c) async {
      c.dismiss();
      await c.check();
    },
    expect: () => [_dismissed],
    verify: (c) => expect(c.state.showPrompt, isFalse),
  );

  blocTest<NotificationPermissionCubit, NotificationPermissionState>(
    'dismissed then enabled elsewhere -> enabled',
    build: build,
    seed: () => _dismissed,
    act: (c) => c.check(),
    expect: () => [_enabled],
  );

  blocTest<NotificationPermissionCubit, NotificationPermissionState>(
    'dismiss is a no-op unless the prompt is showing',
    build: build,
    seed: () => _enabled,
    act: (c) => c.dismiss(),
    expect: () => <NotificationPermissionState>[],
  );
}
