import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/feedback/haptics.dart';

import '../../helpers/fakes.dart';

void main() {
  test('plays while enabled and follows the setting', () async {
    final settings = FakeSettingsRepository();
    final played = <HapticKind>[];
    final haptics = Haptics.withPerformer(settings, (k) async => played.add(k));
    addTearDown(haptics.dispose);

    haptics.play(HapticKind.success);
    await settings.save(settings.current.copyWith(hapticsEnabled: false));
    await Future<void>.delayed(Duration.zero);
    haptics.play(HapticKind.celebrate);
    await settings.save(settings.current.copyWith(hapticsEnabled: true));
    await Future<void>.delayed(Duration.zero);
    haptics.play(HapticKind.light);
    expect(played, [HapticKind.success, HapticKind.light]);
  });

  testWidgets('context.haptic uses the provided Haptics and is a no-op without one', (tester) async {
    final played = <HapticKind>[];
    final haptics = Haptics.withPerformer(FakeSettingsRepository(), (k) async => played.add(k));
    addTearDown(haptics.dispose);
    late BuildContext withProvider;
    late BuildContext without;
    await tester.pumpWidget(
      Column(
        children: [
          RepositoryProvider<Haptics>.value(
            value: haptics,
            child: Builder(
              builder: (c) {
                withProvider = c;
                return const SizedBox();
              },
            ),
          ),
          Builder(
            builder: (c) {
              without = c;
              return const SizedBox();
            },
          ),
        ],
      ),
    );
    withProvider.haptic(HapticKind.selection);
    without.haptic(HapticKind.selection);
    expect(played, [HapticKind.selection]);
  });
}
