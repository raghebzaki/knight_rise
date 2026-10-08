import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/theme/widgets/knight_ring.dart';

import '../../helpers/pump_app.dart';

void main() {
  Widget ring(double progress, {bool reduced = false}) => themedApp(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Center(
        child: KnightRing(
          segments: [RingSegment(progress: progress, color: Colors.cyan)],
        ),
      ),
    ),
  );

  double scale(WidgetTester tester) => tester
      .widget<ScaleTransition>(find.descendant(of: find.byType(KnightRing), matching: find.byType(ScaleTransition)))
      .scale
      .value;

  int sweepDuration(WidgetTester tester) =>
      tester.widget<TweenAnimationBuilder<double>>(find.byType(TweenAnimationBuilder<double>)).duration.inMilliseconds;

  testWidgets('pulses once when a ring reaches 100 %', (tester) async {
    await tester.pumpWidget(ring(0.9));
    await tester.pumpAndSettle();
    expect(scale(tester), 1);

    await tester.pumpWidget(ring(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(scale(tester), greaterThan(1));
    await tester.pumpAndSettle();
    expect(scale(tester), 1);

    // Staying at 100 % does not pulse again.
    await tester.pumpWidget(ring(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(scale(tester), 1);
  });

  testWidgets('a ring that starts at 100 % does not pulse', (tester) async {
    await tester.pumpWidget(ring(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(scale(tester), 1);
  });

  testWidgets('reduced motion: no sweep animation and no pulse', (tester) async {
    await tester.pumpWidget(ring(0.5, reduced: true));
    expect(sweepDuration(tester), 0);
    await tester.pumpWidget(ring(1, reduced: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(scale(tester), 1);
  });

  testWidgets('600 ms sweep with motion on', (tester) async {
    await tester.pumpWidget(ring(0.5));
    expect(sweepDuration(tester), 600);
    await tester.pumpAndSettle();
  });
}
