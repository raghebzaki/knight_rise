import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';
import 'package:knight_rise/features/work_hours/domain/usecases/day_override_usecases.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeDayOverrideRepository repo;
  final today = DateTime.utc(2026, 10, 5);
  final tomorrow = DateTime.utc(2026, 10, 6);

  setUp(() => repo = FakeDayOverrideRepository());

  test('SetDayOff stores an off override', () async {
    final o = await SetDayOff(repo)(today);
    expect(o, DayOverride(date: today, kind: DayOverrideKind.off));
    expect(repo.all, [o]);
  });

  test('SetDayOff normalizes a date-time to its calendar date', () async {
    await SetDayOff(repo)(DateTime(2026, 10, 5, 14, 30));
    expect(repo.all.single.date, today);
  });

  test('ExtendWorkDay accumulates and caps at 240', () async {
    final extend = ExtendWorkDay(repo);
    expect((await extend(today, 60))!.extendMinutes, 60);
    expect((await extend(today, 60))!.extendMinutes, 120);
    expect((await extend(today, 90))!.extendMinutes, 210);
    expect((await extend(today, 60))!.extendMinutes, 240);
    expect((await extend(today, 60))!.extendMinutes, 240);
    expect(repo.all.single.kind, DayOverrideKind.extend);
  });

  test('ExtendWorkDay is per date', () async {
    final extend = ExtendWorkDay(repo);
    await extend(today, 60);
    await extend(tomorrow, 30);
    expect({for (final o in repo.all) o.date: o.extendMinutes}, {today: 60, tomorrow: 30});
  });

  test('ExtendWorkDay replaces a day off and ignores non-positive minutes', () async {
    await SetDayOff(repo)(today);
    expect(await ExtendWorkDay(repo)(today, 0), DayOverride(date: today, kind: DayOverrideKind.off));
    expect((await ExtendWorkDay(repo)(today, 30))!.kind, DayOverrideKind.extend);
    expect(repo.all.single.extendMinutes, 30);
    expect(await ExtendWorkDay(repo)(tomorrow, -5), isNull);
  });

  test('ClearDayOverride removes only that date', () async {
    await SetDayOff(repo)(today);
    await SetDayOff(repo)(tomorrow);
    await ClearDayOverride(repo)(today);
    expect(repo.all.map((o) => o.date), [tomorrow]);
    await ClearDayOverride(repo)(today); // already gone: fine
    expect(repo.all.length, 1);
  });
}
