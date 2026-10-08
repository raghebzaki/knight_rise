import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/quest_log/domain/services/history_series.dart';
import 'package:knight_rise/features/quest_log/presentation/widgets/history_chart.dart';

import '../../helpers/pump_app.dart';

void main() {
  final series = HistorySeries(
    range: HistoryRange.week,
    days: [
      for (var i = 0; i < 7; i++)
        HistoryDay(date: DateTime.utc(2026, 10, 7 + i), kind: HistoryDayKind.work, percent: 10.0 * (i + 1)),
    ],
    stats: const HistoryStats(workDays: 7, goalDays: 0, focusMinutes: 0, bestStreak: 0),
  );

  Widget chart({bool reduced = false}) => themedApp(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: HistoryChart(series: series, color: Colors.blue, thresholdPercent: 70, semanticsLabel: 'summary'),
    ),
  );

  List<double> bars(WidgetTester tester) =>
      tester.widget<BarChart>(find.byType(BarChart)).data.barGroups.map((g) => g.barRods.single.toY).toList();

  testWidgets('bars start at the baseline and grow in on the next frame', (tester) async {
    await tester.pumpWidget(chart());
    expect(bars(tester), everyElement(0));
    expect(tester.widget<BarChart>(find.byType(BarChart)).duration, const Duration(milliseconds: 600));
    await tester.pump();
    expect(bars(tester), [10, 20, 30, 40, 50, 60, 70]);
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion: real values on the first frame, no animation', (tester) async {
    await tester.pumpWidget(chart(reduced: true));
    expect(bars(tester), [10, 20, 30, 40, 50, 60, 70]);
    expect(tester.widget<BarChart>(find.byType(BarChart)).duration, Duration.zero);
  });
}
