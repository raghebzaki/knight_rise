import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/splash/presentation/animated_splash.dart';

import '../../helpers/pump_app.dart';

double opacityOf(WidgetTester tester, String key) => tester.widget<Opacity>(find.byKey(Key(key))).opacity;

double markScale(WidgetTester tester) => tester
    .widget<Transform>(
      find.descendant(of: find.byKey(const Key('splash-mark')), matching: find.byType(Transform)).first,
    )
    .transform
    .storage[0]; // x scale (getMaxScaleOnAxis would include z = 1)

Widget splash({required VoidCallback onFinished, bool reduced = false}) => themedApp(
  MediaQuery(
    data: MediaQueryData(size: const Size(390, 844), disableAnimations: reduced),
    child: AnimatedSplash(onFinished: onFinished),
  ),
);

void main() {
  testWidgets('timeline: shield in, crest glow pulse, staggered title and tagline, then finish', (tester) async {
    var finished = 0;
    await tester.pumpWidget(splash(onFinished: () => finished++));

    // t = 0: nothing visible yet.
    expect(opacityOf(tester, 'splash-mark'), 0);
    expect(opacityOf(tester, 'splash-title'), 0);
    expect(opacityOf(tester, 'splash-glow'), 0);
    expect(markScale(tester), closeTo(0.82, 0.01));

    // 350 ms: the shield is fading and scaling in; the text has not started.
    await tester.pump(const Duration(milliseconds: 350));
    expect(opacityOf(tester, 'splash-mark'), inExclusiveRange(0.5, 1));
    expect(markScale(tester), inExclusiveRange(0.82, 1.1));
    expect(opacityOf(tester, 'splash-title'), 0);

    // 700 ms: shield settled at full size; the title is rising, the tagline not yet.
    await tester.pump(const Duration(milliseconds: 350));
    expect(opacityOf(tester, 'splash-mark'), 1);
    expect(markScale(tester), closeTo(1, 0.01));
    expect(opacityOf(tester, 'splash-title'), inExclusiveRange(0, 1));
    expect(opacityOf(tester, 'splash-tagline'), 0);

    // 850 ms: crest glow near its peak.
    await tester.pump(const Duration(milliseconds: 150));
    expect(opacityOf(tester, 'splash-glow'), closeTo(0.95, 0.05));

    // 1300 ms: all text in; glow easing down to its resting level.
    await tester.pump(const Duration(milliseconds: 450));
    expect(opacityOf(tester, 'splash-title'), 1);
    expect(opacityOf(tester, 'splash-tagline'), 1);
    expect(opacityOf(tester, 'splash-glow'), inExclusiveRange(0.45, 0.95));

    // Not finished before 1.9 s, finished exactly once after.
    await tester.pump(const Duration(milliseconds: 550)); // 1850 ms
    expect(finished, 0);
    await tester.pump(const Duration(milliseconds: 60));
    expect(finished, 1);
    expect(opacityOf(tester, 'splash-glow'), closeTo(0.45, 0.01));
    await tester.pump(const Duration(seconds: 1));
    expect(finished, 1);
  });

  testWidgets('reduced motion: final frame immediately, finished after the first frame', (tester) async {
    var finished = 0;
    await tester.pumpWidget(splash(onFinished: () => finished++, reduced: true));
    expect(opacityOf(tester, 'splash-mark'), 1);
    expect(opacityOf(tester, 'splash-title'), 1);
    expect(opacityOf(tester, 'splash-tagline'), 1);
    expect(markScale(tester), 1);
    await tester.pump();
    expect(finished, 1);
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'nothing keeps animating');
  });

  testWidgets('screen readers hear the app name, not the artwork', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(splash(onFinished: () {}));
    expect(find.bySemanticsLabel('Knight Rise'), findsOneWidget);
    handle.dispose();
    await tester.pump(kSplashDuration);
  });

  group('SplashOverlay', () {
    Widget overlay({required bool show, required VoidCallback onFinished, bool reduced = false}) => themedApp(
      MediaQuery(
        data: MediaQueryData(size: const Size(390, 844), disableAnimations: reduced),
        child: SplashOverlay(
          show: show,
          onFinished: onFinished,
          child: Scaffold(
            body: Center(
              child: TextButton(onPressed: () {}, child: const Text('first route')),
            ),
          ),
        ),
      ),
    );

    testWidgets('the first route is built underneath and revealed with a fade', (tester) async {
      var show = true;
      late StateSetter set;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return overlay(show: show, onFinished: () => set(() => show = false));
          },
        ),
      );
      expect(find.text('first route'), findsOneWidget, reason: 'already built under the splash');
      expect(find.byType(AnimatedSplash), findsOneWidget);

      await tester.pump(kSplashDuration + const Duration(milliseconds: 20));
      expect(show, isFalse);
      await tester.pump(kSplashFadeOut ~/ 2);
      expect(find.byType(AnimatedSplash), findsOneWidget, reason: 'fading out');
      await tester.pump(kSplashFadeOut);
      expect(find.byType(AnimatedSplash), findsNothing);
      await tester.tap(find.text('first route'));
    });

    testWidgets('reduced motion: no splash time and no fade', (tester) async {
      var show = true;
      late StateSetter set;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return overlay(show: show, onFinished: () => set(() => show = false), reduced: true);
          },
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(show, isFalse);
      expect(find.byType(AnimatedSplash), findsNothing);
    });
  });
}
