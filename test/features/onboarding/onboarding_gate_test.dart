import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/onboarding/presentation/onboarding_gate.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeSettingsRepository settings;

  setUp(() => settings = FakeSettingsRepository());

  test('is not completed before load', () {
    final gate = OnboardingGate(settings);
    addTearDown(gate.dispose);
    expect(gate.completed, isFalse);
  });

  test('load reads a fresh install as not completed', () async {
    final gate = OnboardingGate(settings);
    addTearDown(gate.dispose);
    await gate.load();
    expect(gate.completed, isFalse);
  });

  test('load reads an upgraded install as completed', () async {
    await settings.save(settings.current.copyWith(onboardingCompleted: true));
    final gate = OnboardingGate(settings);
    addTearDown(gate.dispose);
    await gate.load();
    expect(gate.completed, isTrue);
  });

  test('watches the setting and notifies once per change', () async {
    final gate = OnboardingGate(settings);
    addTearDown(gate.dispose);
    await gate.load();
    var notified = 0;
    gate.addListener(() => notified++);

    await settings.save(settings.current.copyWith(waterPerTapMl: 300));
    await pumpEventQueue();
    expect(notified, 0);

    await settings.save(settings.current.copyWith(onboardingCompleted: true));
    await pumpEventQueue();
    expect(gate.completed, isTrue);
    expect(notified, 1);
  });
}
