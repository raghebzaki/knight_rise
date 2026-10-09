import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/splash/presentation/animated_splash.dart';
import 'package:knight_rise/features/splash/presentation/splash_gate.dart';

import '../../helpers/pump_app.dart';

/// The mechanism `KnightRiseApp` uses (listen to the gate, drop the splash
/// flag), around the real [SplashOverlay]; pumping the full app needs most of
/// the DI graph.
class _Harness extends StatefulWidget {
  const _Harness(this.gate);

  final SplashGate gate;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late bool _show = !widget.gate.dismissed;

  @override
  void initState() {
    super.initState();
    widget.gate.addListener(_onGate);
  }

  void _onGate() {
    if (widget.gate.dismissed && _show && mounted) setState(() => _show = false);
  }

  @override
  void dispose() {
    widget.gate.removeListener(_onGate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SplashOverlay(show: _show, onFinished: () => setState(() => _show = false), child: const Text('break page'));
}

void main() {
  testWidgets('dismissing the gate while the splash plays removes it and shows the page', (tester) async {
    final gate = SplashGate();
    await tester.pumpWidget(themedApp(_Harness(gate)));
    expect(find.byType(AnimatedSplash), findsOneWidget);

    gate.dismiss();
    await tester.pump();
    await tester.pump(kSplashFadeOut + const Duration(milliseconds: 50));
    expect(find.byType(AnimatedSplash), findsNothing);
    expect(find.text('break page'), findsOneWidget);
  });

  testWidgets('an already dismissed gate never shows the splash', (tester) async {
    final gate = SplashGate()..dismiss();
    await tester.pumpWidget(themedApp(_Harness(gate)));
    expect(find.byType(AnimatedSplash), findsNothing);
  });

  test('dismiss notifies once and is sticky', () {
    final gate = SplashGate();
    var calls = 0;
    gate
      ..addListener(() => calls++)
      ..dismiss()
      ..dismiss();
    expect(gate.dismissed, isTrue);
    expect(calls, 1);
  });
}
