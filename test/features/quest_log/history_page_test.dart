import 'package:fl_chart/fl_chart.dart';
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
import '../../helpers/pump_app.dart';
import '../../helpers/quest_log_harness.dart';
import '../../helpers/tz.dart';

DateTime d(int n) => DateTime.utc(2026, 10, n);

void main() {
  /// Today is Wed 14 Oct; the week is Wed 7 .. Tue 13 (Fri 9 / Sat 10 rest).
  final history = <DailySummary>[
    pastDay(d(7), focusMinutes: 30),
    pastDay(d(8), qualified: false).copyWith(
      waterMl: 1000,
      routines: [
        const RoutineDaySummary(type: RoutineType.hydration, done: 4, target: 8, enabled: true),
        const RoutineDaySummary(type: RoutineType.stretch, done: 3, target: 6, enabled: true),
        const RoutineDaySummary(type: RoutineType.eyeRest, done: 6, target: 12, enabled: true),
      ],
    ),
    pastDay(d(9), workDay: false),
    pastDay(d(10), workDay: false),
    pastDay(d(11), focusMinutes: 45),
    pastDay(d(12)),
    pastDay(d(13)),
  ];

  Future<void> pumpPage(
    WidgetTester tester, {
    List<DailySummary>? summaries,
    KnightPalette palette = KnightPalette.midnight,
  }) async {
    useTallView(tester);
    HistoryCubit cubit() => HistoryCubit(
      FakeDailySummaryRepository(summaries ?? history),
      FakeSettingsRepository(),
      FixedClock(at(cairo, 2026, 10, 14, 10)),
      FakeLocationProvider(cairo),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KnightTheme.build(palette),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HistoryPage(cubitFactory: cubit),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // chart animation
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  BarChartData chart(WidgetTester tester) => tester.widget<BarChart>(find.byType(BarChart)).data;
  String tile(WidgetTester tester, String key) => [
    for (final t in tester.widgetList<Text>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text))))
      t.data,
  ].join(' | ');

  testWidgets('7 days, all routines: bars, goal line, key and stat tiles', (tester) async {
    await pumpPage(tester);
    expect(find.text('HISTORY'), findsOneWidget);
    final data = chart(tester);
    expect(data.barGroups, hasLength(7));
    expect(data.barGroups.map((g) => g.barRods.single.toY), [100, 50, 100, 100, 100, 100, 100]);
    expect(data.extraLinesData.horizontalLines.single.y, 70);
    expect(data.maxY, 100);
    expect(find.text('Work day'), findsOneWidget);
    expect(find.text('Rest day'), findsOneWidget);

    expect(tile(tester, 'stat-completion'), 'Completion rate | 90% | 4 of 5 work days met the goal');
    expect(tile(tester, 'stat-focus'), 'Focus time | 1 h 15 min | in this period');
    expect(tile(tester, 'stat-water'), 'Average water | 1,800 ml | per work day');
    expect(tile(tester, 'stat-streak'), 'Best streak | 3 days | in this period');
    await unmount(tester);
  });

  testWidgets('the chart is one semantics node with a summary; the canvas is excluded', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpPage(tester);
    expect(
      find.bySemanticsLabel('All routines, last 7 days: average 90%, goal met on 4 of 5 work days.'),
      findsOneWidget,
    );
    handle.dispose();
    await unmount(tester);
  });

  testWidgets('a routine filter recolors to that routine and rescopes the stats', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('history-filter-stretch')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final rods = chart(tester).barGroups.map((g) => g.barRods.single).toList();
    expect(rods.map((r) => r.toY), [100, 50, 100, 100, 100, 100, 100]);
    expect(rods.first.color, KnightPalette.midnight.stretch);
    expect(tile(tester, 'stat-completion'), 'Completion rate | 90% | 4 of 5 work days met the goal');
    expect(find.text('Quick stretch'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('30 days shows 30 bars and labels every 7th day back from yesterday', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('30 days'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(chart(tester).barGroups, hasLength(30));
    // Labeled: 13, 6 Oct, 29, 22, 15 Sep.
    for (final label in ['Oct 13', 'Oct 6', 'Sep 29', 'Sep 22', 'Sep 15']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Oct 12'), findsNothing);
    await unmount(tester);
  });

  testWidgets('table view lists every day newest first with its status', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('history-table-toggle')));
    await tester.pump();
    expect(find.byType(BarChart), findsNothing);
    final table = find.byKey(const Key('history-table'));
    final rows = [
      for (final t in tester.widgetList<Text>(find.descendant(of: table, matching: find.byType(Text)))) t.data,
    ];
    expect(rows, [
      'Tue, Oct 13', '100% · Goal met', //
      'Mon, Oct 12', '100% · Goal met',
      'Sun, Oct 11', '100% · Goal met',
      'Sat, Oct 10', '100% · Rest day',
      'Fri, Oct 9', '100% · Rest day',
      'Thu, Oct 8', '50% · Below goal',
      'Wed, Oct 7', '100% · Goal met',
    ]);
    await tester.tap(find.byKey(const Key('history-table-toggle')));
    await tester.pump();
    expect(find.byType(BarChart), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('no finalized days yet: empty state instead of the chart', (tester) async {
    await pumpPage(tester, summaries: const []);
    expect(find.byKey(const Key('history-empty')), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
    await unmount(tester);
  });

  for (final (name, palette) in [('Midnight', KnightPalette.midnight), ('AMOLED', KnightPalette.amoled)]) {
    testWidgets('$name: bars bind to the palette tokens, rest days dimmed, recessive grid', (tester) async {
      await pumpPage(tester, palette: palette);
      var rods = chart(tester).barGroups.map((g) => g.barRods.single).toList();
      expect(rods.first.color, palette.secondary); // all routines
      expect(rods[2].color, palette.secondary.withValues(alpha: HistoryChart.restOpacity)); // Fri rest day
      expect(chart(tester).gridData.getDrawingHorizontalLine(50).color, palette.outline);

      for (final type in RoutineType.values) {
        await tester.tap(find.byKey(Key('history-filter-${type.name}')));
        await tester.pump();
        rods = chart(tester).barGroups.map((g) => g.barRods.single).toList();
        final expected = switch (type) {
          RoutineType.hydration => palette.hydration,
          RoutineType.stretch => palette.stretch,
          RoutineType.eyeRest => palette.eyeRest,
        };
        expect(rods.first.color, expected, reason: type.name);
        expect(rods.first.width, lessThanOrEqualTo(24));
      }
      await tester.pump(const Duration(seconds: 1));
      await unmount(tester);
    });
  }
}
