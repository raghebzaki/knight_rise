import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/features/work_hours/data/drift_day_override_repository.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';

DateTime d(int day) => DateTime.utc(2026, 10, day);

void main() {
  late AppDatabase db;
  late DriftDayOverrideRepository repo;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftDayOverrideRepository(db);
  });
  tearDown(() => db.close());

  test('set round-trips off and extend overrides, keyed by YYYY-MM-DD', () async {
    await repo.set(DayOverride(date: d(5), kind: DayOverrideKind.off));
    await repo.set(DayOverride(date: d(6), kind: DayOverrideKind.extend, extendMinutes: 90));
    expect(await repo.getFrom(d(1)), [
      DayOverride(date: d(5), kind: DayOverrideKind.off),
      DayOverride(date: d(6), kind: DayOverrideKind.extend, extendMinutes: 90),
    ]);
    final rows = await db.select(db.dayOverrides).get();
    expect(rows.map((r) => r.date), ['2026-10-05', '2026-10-06']);
  });

  test('set replaces the override of the same date', () async {
    await repo.set(DayOverride(date: d(5), kind: DayOverrideKind.off));
    await repo.set(DayOverride(date: d(5), kind: DayOverrideKind.extend, extendMinutes: 30));
    expect(await repo.getFrom(d(5)), [DayOverride(date: d(5), kind: DayOverrideKind.extend, extendMinutes: 30)]);
  });

  test('a time of day on the date is ignored (only the calendar date is the key)', () async {
    await repo.set(DayOverride(date: DateTime(2026, 10, 5, 17, 45), kind: DayOverrideKind.off));
    expect((await repo.getFrom(d(5))).single.date, d(5));
  });

  test('getFrom / watchFrom only return dates on or after the given date, ordered', () async {
    for (final day in [9, 4, 5, 6]) {
      await repo.set(DayOverride(date: d(day), kind: DayOverrideKind.off));
    }
    expect((await repo.getFrom(d(5))).map((o) => o.date.day), [5, 6, 9]);
    expect((await repo.watchFrom(d(6)).first).map((o) => o.date.day), [6, 9]);
    expect(await repo.getFrom(d(10)), isEmpty);
  });

  test('clear removes one date and is idempotent; watchFrom reacts', () async {
    await repo.set(DayOverride(date: d(5), kind: DayOverrideKind.off));
    await repo.set(DayOverride(date: d(6), kind: DayOverrideKind.off));
    final emissions = <List<int>>[];
    final sub = repo.watchFrom(d(1)).listen((l) => emissions.add(l.map((o) => o.date.day).toList()));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await repo.clear(d(5));
    await repo.clear(d(5));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(emissions.first, [5, 6]);
    expect(emissions.last, [6]);
    expect((await repo.getFrom(d(1))).map((o) => o.date.day), [6]);
  });

  test('deleteBefore removes overrides dated strictly before the date', () async {
    for (final day in [1, 4, 5, 9]) {
      await repo.set(DayOverride(date: d(day), kind: DayOverrideKind.off));
    }
    expect(await repo.deleteBefore(DateTime(2026, 10, 5, 18)), 2);
    expect((await repo.getFrom(d(1))).map((o) => o.date.day), [5, 9]);
    expect(await repo.deleteBefore(d(5)), 0);
  });
}
