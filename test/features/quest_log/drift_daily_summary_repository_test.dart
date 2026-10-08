import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/features/quest_log/data/drift_daily_summary_repository.dart';
import 'package:knight_rise/features/quest_log/domain/entities/daily_summary.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';

DateTime d(int day) => DateTime.utc(2026, 10, day);

DailySummary summary(
  int day, {
  bool isWorkDay = true,
  int waterMl = 1500,
  bool qualified = true,
  int thresholdPercent = 70,
  List<RoutineDaySummary>? routines,
}) => DailySummary(
  date: d(day),
  isWorkDay: isWorkDay,
  waterMl: waterMl,
  waterTargetMl: 2000,
  focusMinutes: 50,
  thresholdPercent: thresholdPercent,
  qualified: qualified,
  finalizedAt: DateTime.utc(2026, 10, day + 1, 0, 5),
  routines:
      routines ??
      const [
        RoutineDaySummary(type: RoutineType.hydration, done: 6, target: 8, enabled: true),
        RoutineDaySummary(type: RoutineType.stretch, done: 5, target: 6, enabled: true),
        RoutineDaySummary(type: RoutineType.eyeRest, done: 0, target: 12, enabled: false),
      ],
);

void main() {
  late AppDatabase db;
  late DriftDailySummaryRepository repo;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftDailySummaryRepository(db);
  });
  tearDown(() => db.close());

  test('upsert round-trips every field, keyed by YYYY-MM-DD', () async {
    await repo.upsert(summary(5));
    final stored = (await repo.getFrom(d(1))).single;
    expect(stored.copyWith(finalizedAt: summary(5).finalizedAt), summary(5));
    expect(stored.finalizedAt.isAtSameMomentAs(summary(5).finalizedAt), isTrue);
    expect((await db.select(db.dailySummaries).get()).single.date, '2026-10-05');
    expect(await db.select(db.dailyRoutineSummaries).get(), hasLength(3));
  });

  test('routines come back in RoutineType order whatever the insert order', () async {
    await repo.upsert(
      summary(
        5,
        routines: const [
          RoutineDaySummary(type: RoutineType.eyeRest, done: 1, target: 12, enabled: true),
          RoutineDaySummary(type: RoutineType.hydration, done: 2, target: 8, enabled: true),
        ],
      ),
    );
    expect((await repo.getFrom(d(5))).single.routines.map((r) => r.type), [RoutineType.hydration, RoutineType.eyeRest]);
  });

  test('upsert replaces the day and its routine rows instead of appending', () async {
    await repo.upsert(summary(5));
    await repo.upsert(
      summary(
        5,
        waterMl: 2250,
        qualified: false,
        thresholdPercent: 90,
        routines: const [RoutineDaySummary(type: RoutineType.stretch, done: 6, target: 6, enabled: true)],
      ),
    );
    final stored = (await repo.getFrom(d(1))).single;
    expect(stored.waterMl, 2250);
    expect(stored.qualified, isFalse);
    expect(stored.thresholdPercent, 90);
    expect(stored.routines, const [RoutineDaySummary(type: RoutineType.stretch, done: 6, target: 6, enabled: true)]);
    expect(await db.select(db.dailyRoutineSummaries).get(), hasLength(1));
  });

  test('a day without routine rows (rest day) is still returned', () async {
    await repo.upsert(summary(4, isWorkDay: false, qualified: false, routines: const []));
    final stored = (await repo.getFrom(d(1))).single;
    expect(stored.isWorkDay, isFalse);
    expect(stored.routines, isEmpty);
  });

  test('getFrom / watchFrom return days on or after the date, oldest first', () async {
    for (final day in [9, 4, 5, 6]) {
      await repo.upsert(summary(day));
    }
    expect((await repo.getFrom(d(5))).map((s) => s.date.day), [5, 6, 9]);
    expect((await repo.watchFrom(d(6)).first).map((s) => s.date.day), [6, 9]);
    expect(await repo.getFrom(d(10)), isEmpty);
    expect((await repo.getFrom(DateTime(2026, 10, 5, 23, 59))).first.date, d(5));
  });

  test('watchFrom emits again after an upsert', () async {
    await repo.upsert(summary(4));
    final emissions = <List<int>>[];
    final sub = repo.watchFrom(d(1)).listen((l) => emissions.add(l.map((s) => s.date.day).toList()));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await repo.upsert(summary(5));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(emissions.first, [4]);
    expect(emissions.last, [4, 5]);
  });

  test('latestDate is null when empty, then the newest stored date', () async {
    expect(await repo.latestDate(), isNull);
    for (final day in [5, 9, 6]) {
      await repo.upsert(summary(day));
    }
    expect(await repo.latestDate(), d(9));
  });

  test('summaries spanning a month boundary sort chronologically', () async {
    await repo.upsert(summary(1).copyWith(date: DateTime.utc(2026, 11, 2)));
    await repo.upsert(summary(30).copyWith(date: DateTime.utc(2026, 9, 30)));
    expect((await repo.getFrom(DateTime.utc(2026, 9, 2))).map((s) => s.date), [
      DateTime.utc(2026, 9, 30),
      DateTime.utc(2026, 11, 2),
    ]);
    expect(await repo.latestDate(), DateTime.utc(2026, 11, 2));
  });
}
