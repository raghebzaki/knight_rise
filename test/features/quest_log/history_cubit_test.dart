import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/features/quest_log/domain/services/history_series.dart';
import 'package:knight_rise/features/quest_log/presentation/history_cubit.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';

import '../../helpers/fakes.dart';
import '../../helpers/quest_log_harness.dart';
import '../../helpers/tz.dart';

DateTime d(int n) => DateTime.utc(2026, 10, n);

void main() {
  late FixedClock clock;
  late FakeDailySummaryRepository summaries;
  late FakeSettingsRepository settings;

  setUp(() {
    clock = FixedClock(at(cairo, 2026, 10, 14, 10));
    summaries = FakeDailySummaryRepository([
      for (final n in [1, 8, 12, 13]) pastDay(d(n)),
    ]);
    settings = FakeSettingsRepository();
  });

  HistoryCubit cubit() {
    final c = HistoryCubit(summaries, settings, clock, FakeLocationProvider(cairo))..start();
    addTearDown(c.close);
    return c;
  }

  Future<HistoryState> ready(HistoryCubit c) => c.stream.firstWhere((s) => s.status == HistoryStatus.ready);

  test('loads the last 30 days with the current goal; defaults to 7 days, all routines', () async {
    final c = cubit();
    expect(c.state.status, HistoryStatus.loading);
    expect(c.state.today, d(14));
    final s = await ready(c);
    expect(s.summaries.map((x) => x.date.day), [1, 8, 12, 13]);
    expect(s.thresholdPercent, 70);
    expect(s.range, HistoryRange.week);
    expect(s.routine, isNull);
    expect(s.series.days.where((x) => x.kind == HistoryDayKind.work).map((x) => x.date.day), [8, 12, 13]);
  });

  test('range, routine and table toggles', () async {
    final c = cubit();
    await ready(c);
    c
      ..setRange(HistoryRange.month)
      ..setRoutine(RoutineType.stretch)
      ..toggleTable();
    expect(c.state.series.days, hasLength(30));
    expect(c.state.series.routine, RoutineType.stretch);
    expect(c.state.showTable, isTrue);
    c
      ..setRoutine(null)
      ..toggleTable();
    expect(c.state.series.routine, isNull);
    expect(c.state.showTable, isFalse);
  });

  test('new summaries and a changed goal flow in', () async {
    final c = cubit();
    await ready(c);
    await summaries.upsert(pastDay(d(11)));
    await settings.save(settings.current.copyWith(streakThresholdPercent: 85));
    await Future<void>.delayed(Duration.zero);
    expect(c.state.summaries.map((x) => x.date.day), [1, 8, 11, 12, 13]);
    expect(c.state.thresholdPercent, 85);
  });

  test('refresh after midnight moves the window and keeps the filters', () async {
    final c = cubit();
    await ready(c);
    c.setRoutine(RoutineType.hydration);
    clock.current = at(cairo, 2026, 10, 15, 0, 5);
    c.refresh();
    expect(c.state.today, d(15));
    expect(c.state.routine, RoutineType.hydration);
    await Future<void>.delayed(Duration.zero);
    expect(c.state.series.days.last.date, d(14));
  });
}
