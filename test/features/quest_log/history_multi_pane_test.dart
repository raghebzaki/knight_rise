import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/features/quest_log/domain/entities/daily_summary.dart';
import 'package:knight_rise/features/quest_log/presentation/history_cubit.dart';
import 'package:knight_rise/features/quest_log/presentation/history_page.dart';
import 'package:knight_rise/features/quest_log/presentation/widgets/history_chart.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';
import '../../helpers/quest_log_harness.dart';
import '../../helpers/tz.dart';

DateTime d(int n) => DateTime.utc(2026, 10, n);

/// Today is Wed 14 Oct; the week is Wed 7 .. Tue 13 (Fri 9 / Sat 10 rest).
final history = <DailySummary>[
  pastDay(d(7), focusMinutes: 30),
  pastDay(d(8), qualified: false).copyWith(
    waterMl: 1000,
    focusMinutes: 20,
    routines: [
      const RoutineDaySummary(type: RoutineType.hydration, done: 4, target: 8, enabled: true),
      const RoutineDaySummary(type: RoutineType.stretch, done: 3, target: 6, enabled: true),
      const RoutineDaySummary(type: RoutineType.eyeRest, done: 6, target: 12, enabled: false),
    ],
  ),
  pastDay(d(9), workDay: false),
  pastDay(d(10), workDay: false),
  pastDay(d(11), focusMinutes: 45),
  pastDay(d(12)),
  pastDay(d(13)),
];

/// Pumps the History page in a [size] window (logical px).
Future<void> pumpHistory(
  WidgetTester tester, {
  Size size = const Size(1300, 900),
  Locale locale = const Locale('en'),
  List<DailySummary>? summaries,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  HistoryCubit cubit() => HistoryCubit(
    FakeDailySummaryRepository(summaries ?? history),
    FakeSettingsRepository(),
    FixedClock(at(cairo, 2026, 10, 14, 10)),
    FakeLocationProvider(cairo),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: KnightTheme.build(KnightPalette.midnight, joinedScript: KnightTheme.isJoinedScript(locale)),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HistoryPage(cubitFactory: cubit),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

String paneDate(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('history-pane-date'))).data!;

/// A point on the plot over bar [index] of 7, near the baseline.
Offset barPoint(WidgetTester tester, int index) {
  final rect = tester.getRect(find.byType(BarChart));
  const leftAxis = 48.0;
  final slot = (rect.width - leftAxis) / 7;
  // The plot sits right of the axis; 28 px bottom band, 8 px top padding.
  return Offset(rect.left + leftAxis + slot * (index + 0.5), rect.bottom - 28 - 10);
}

Future<TestGesture> mouse(WidgetTester tester) async {
  final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: const Offset(1, 1));
  addTearDown(g.removePointer);
  return g;
}

void main() {
  testWidgets('multi-pane: content at 60% and the detail pane at 40%, defaulting to the last work day', (tester) async {
    await pumpHistory(tester);
    final pane = tester.getRect(find.byKey(const Key('history-day-pane')));
    final chart = tester.getRect(find.byType(BarChart));
    expect(chart.right, lessThan(pane.left));
    expect(pane.left, greaterThan(1300 * 0.5));
    expect(paneDate(tester), 'Tuesday, October 13, 2026');
    expect(find.byKey(const Key('history-pane-status')), findsOneWidget);
    expect(find.byKey(const Key('history-pane-unpin')), findsNothing);
  });

  testWidgets('RTL mirrors: the pane is on the left', (tester) async {
    await pumpHistory(tester, locale: const Locale('ar'));
    final pane = tester.getRect(find.byKey(const Key('history-day-pane')));
    final chart = tester.getRect(find.byType(BarChart));
    expect(pane.right, lessThan(chart.left));
  });

  testWidgets('compact has no pane and keeps the tooltip', (tester) async {
    await pumpHistory(tester, size: const Size(400, 900));
    expect(find.byKey(const Key('history-day-pane')), findsNothing);
    expect(tester.widget<BarChart>(find.byType(BarChart)).data.barTouchData.handleBuiltInTouches, isTrue);
  });

  testWidgets('multi-pane disables the built-in tooltip', (tester) async {
    await pumpHistory(tester);
    expect(tester.widget<BarChart>(find.byType(BarChart)).data.barTouchData.handleBuiltInTouches, isFalse);
  });

  testWidgets('hovering a bar previews its day; leaving restores the default', (tester) async {
    await pumpHistory(tester);
    final g = await mouse(tester);
    await g.moveTo(barPoint(tester, 1));
    await tester.pump();
    expect(paneDate(tester), 'Thursday, October 8, 2026');
    expect(tester.widget<Text>(find.byKey(const Key('history-pane-status'))).data, '50% · Below goal');
    await g.moveTo(const Offset(5, 5));
    await tester.pump();
    expect(paneDate(tester), 'Tuesday, October 13, 2026');
  });

  testWidgets('clicking a bar pins it; preview wins while hovering; unpin releases', (tester) async {
    await pumpHistory(tester);
    final g = await mouse(tester);
    await g.moveTo(barPoint(tester, 1));
    await g.down(barPoint(tester, 1));
    await g.up();
    await tester.pump();
    expect(find.byKey(const Key('history-pane-pinned')), findsOneWidget);

    await g.moveTo(barPoint(tester, 4));
    await tester.pump();
    expect(paneDate(tester), 'Sunday, October 11, 2026');
    expect(find.byKey(const Key('history-pane-pinned')), findsNothing);

    await g.moveTo(const Offset(5, 5));
    await tester.pump();
    expect(paneDate(tester), 'Thursday, October 8, 2026');
    expect(find.byKey(const Key('history-pane-pinned')), findsOneWidget);

    await tester.tap(find.byKey(const Key('history-pane-unpin')));
    await tester.pump();
    expect(paneDate(tester), 'Tuesday, October 13, 2026');
    expect(find.byKey(const Key('history-pane-unpin')), findsNothing);
  });

  testWidgets('the pane breaks the day down per routine, with water and focus', (tester) async {
    await pumpHistory(tester);
    await tester.tap(find.byKey(const Key('history-table-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('history-row-2026-10-08')));
    await tester.pump();
    final pane = find.byKey(const Key('history-day-pane'));
    expect(find.descendant(of: pane, matching: find.text('1,000 / 2,000 ml')), findsOneWidget);
    expect(find.descendant(of: pane, matching: find.text('3 / 6')), findsOneWidget);
    expect(find.descendant(of: pane, matching: find.text('Off')), findsOneWidget);
    expect(find.descendant(of: pane, matching: find.text('20 min')), findsOneWidget);
    expect(find.descendant(of: pane, matching: find.text('50% · Below goal')), findsOneWidget);
  });

  testWidgets('table rows are focusable, pin on activation and toggle off', (tester) async {
    await pumpHistory(tester);
    await tester.tap(find.byKey(const Key('history-table-toggle')));
    await tester.pump();
    final row = find.byKey(const Key('history-row-2026-10-11'));
    expect(tester.widget<InkWell>(row).onTap, isNotNull);
    await tester.tap(row);
    await tester.pump();
    expect(paneDate(tester), 'Sunday, October 11, 2026');
    expect(find.byKey(const Key('history-pane-pinned')), findsOneWidget);
    await tester.tap(row);
    await tester.pump();
    expect(find.byKey(const Key('history-pane-pinned')), findsNothing);
    expect(paneDate(tester), 'Tuesday, October 13, 2026');
  });

  testWidgets('changing the range or the routine clears the pin', (tester) async {
    await pumpHistory(tester);
    await tester.tap(find.byKey(const Key('history-table-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('history-row-2026-10-11')));
    await tester.pump();
    expect(find.byKey(const Key('history-pane-pinned')), findsOneWidget);
    await tester.tap(find.byKey(const Key('history-filter-stretch')));
    await tester.pump();
    expect(find.byKey(const Key('history-pane-pinned')), findsNothing);

    await tester.tap(find.byKey(const Key('history-row-2026-10-11')));
    await tester.pump();
    expect(find.byKey(const Key('history-pane-pinned')), findsOneWidget);
    await tester.tap(find.text('30 days'));
    await tester.pump();
    expect(find.byKey(const Key('history-pane-pinned')), findsNothing);
  });

  testWidgets('no data at all: the pane shows the placeholder', (tester) async {
    await pumpHistory(tester, summaries: const []);
    expect(find.byKey(const Key('history-pane-placeholder')), findsOneWidget);
  });

  testWidgets('touch mapping: hover previews, exit clears, tap-up selects, misses are ignored', (tester) async {
    final hovered = <int?>[];
    final tapped = <int>[];
    BarTouchResponse over(int i) => BarTouchResponse(
      touchLocation: Offset.zero,
      touchChartCoordinate: Offset.zero,
      spot: BarTouchedSpot(BarChartGroupData(x: 0), i, BarChartRodData(toY: 1), 0, null, -1, FlSpot.zero, Offset.zero),
    );
    void route(FlTouchEvent e, BarTouchResponse? r) => routeHistoryTouch(e, r, onHover: hovered.add, onTap: tapped.add);
    route(const FlPointerHoverEvent(PointerHoverEvent()), over(3));
    route(const FlPointerHoverEvent(PointerHoverEvent()), null);
    route(const FlPointerExitEvent(PointerExitEvent()), over(3));
    route(FlTapUpEvent(TapUpDetails(kind: PointerDeviceKind.mouse)), over(2));
    route(FlTapUpEvent(TapUpDetails(kind: PointerDeviceKind.mouse)), null);
    expect(hovered, [3, null, null]);
    expect(tapped, [2]);
  });
}
