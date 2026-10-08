import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/features/cycle/presentation/widgets/countdown_text.dart';

import '../../helpers/pump_app.dart';

void main() {
  test('spoken minutes round up and never go negative', () {
    expect(CountdownText.spokenMinutes(const Duration(minutes: 4, seconds: 59)), 5);
    expect(CountdownText.spokenMinutes(const Duration(minutes: 5)), 5);
    expect(CountdownText.spokenMinutes(const Duration(seconds: 1)), 1);
    expect(CountdownText.spokenMinutes(Duration.zero), 0);
    expect(CountdownText.spokenMinutes(const Duration(seconds: -5)), 0);
  });

  testWidgets('a live region whose label changes per minute, not per second', (tester) async {
    final handle = tester.ensureSemantics();
    final clock = FixedClock(DateTime(2026, 10, 12, 10));
    await tester.pumpWidget(
      RepositoryProvider<Clock>.value(
        value: clock,
        child: themedApp(Center(child: CountdownText(target: DateTime(2026, 10, 12, 10, 2, 30)))),
      ),
    );
    final node = find.byType(CountdownText);
    expect(tester.getSemantics(node), matchesSemantics(label: '3 minutes remaining', isLiveRegion: true));
    expect(find.text('02:30'), findsOneWidget);

    clock.advance(const Duration(seconds: 20)); // 02:10 → still 3 minutes
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('02:10'), findsOneWidget);
    expect(tester.getSemantics(node).label, '3 minutes remaining');

    clock.advance(const Duration(seconds: 70)); // 01:00
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getSemantics(node).label, '1 minute remaining');

    clock.advance(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getSemantics(node).label, 'Less than a minute remaining');
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
