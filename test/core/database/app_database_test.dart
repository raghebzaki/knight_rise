import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/features/routines/data/drift_routine_repository.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/data/drift_reminder_event_repository.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/settings/data/drift_settings_repository.dart';
import 'package:knight_rise/features/work_hours/data/drift_work_schedule_repository.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';

void main() {
  late AppDatabase db;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('seeds default routines, Sun–Thu 09–17, and default settings', () async {
    expect(await DriftRoutineRepository(db).getAll(), Routine.defaults);
    expect(await DriftWorkScheduleRepository(db).get(), WorkSchedule.standard());
    final s = await DriftSettingsRepository(db).get();
    expect(s.themeVariant, ThemeVariant.midnight);
    expect(s.waterPerTapMl, 250);
    expect(s.precisionTiming, isFalse);
    expect(s.timezoneId, isNull);
  });

  test('fresh install seeds onboarding_completed = false and shield_recover_on_exit = true', () async {
    final s = await DriftSettingsRepository(db).get();
    expect(s.onboardingCompleted, isFalse);
    expect(s.shieldRecoverOnExit, isTrue);
    final row = await db.select(db.appSettingsTable).getSingle();
    expect(row.onboardingCompleted, isFalse);
    expect(row.shieldRecoverOnExit, isTrue);
  });

  test('onboardingCompleted and shieldRecoverOnExit round-trip', () async {
    final settings = DriftSettingsRepository(db);
    await settings.save((await settings.get()).copyWith(onboardingCompleted: true, shieldRecoverOnExit: false));
    final s = await settings.get();
    expect(s.onboardingCompleted, isTrue);
    expect(s.shieldRecoverOnExit, isFalse);
    expect(s.themeVariant, ThemeVariant.midnight);
  });

  test('settings timezoneId round-trips and can be cleared', () async {
    final settings = DriftSettingsRepository(db);
    await settings.save((await settings.get()).copyWith(timezoneId: 'Africa/Cairo'));
    expect((await settings.get()).timezoneId, 'Africa/Cairo');
    await settings.save((await settings.get()).copyWith(timezoneId: null));
    expect((await settings.get()).timezoneId, isNull);
  });

  test('routine and settings updates round-trip and stream', () async {
    final routines = DriftRoutineRepository(db);
    final settings = DriftSettingsRepository(db);

    final emitted = routines.watchAll().firstWhere(
      (l) => l.first.intervalMinutes == 30 && l.first.mode == ScheduleMode.fixedGrid,
    );
    await routines.save(Routine.defaults.first.copyWith(intervalMinutes: 30, mode: ScheduleMode.fixedGrid));
    final second = await emitted.timeout(const Duration(seconds: 5));
    expect(second.first.intervalMinutes, 30);
    expect(second.first.mode, ScheduleMode.fixedGrid);

    await settings.save((await settings.get()).copyWith(themeVariant: ThemeVariant.amoled));
    expect((await settings.get()).themeVariant, ThemeVariant.amoled);
  });

  test('fresh install seeds a 70% streak threshold and no retention run', () async {
    final s = await DriftSettingsRepository(db).get();
    expect(s.streakThresholdPercent, 70);
    expect(s.lastRetentionRunAt, isNull);
  });

  test('streakThresholdPercent and lastRetentionRunAt round-trip and can be cleared', () async {
    final settings = DriftSettingsRepository(db);
    final at = DateTime.utc(2026, 10, 8, 3);
    await settings.save((await settings.get()).copyWith(streakThresholdPercent: 85, lastRetentionRunAt: at));
    final s = await settings.get();
    expect(s.streakThresholdPercent, 85);
    expect(s.lastRetentionRunAt!.isAtSameMomentAs(at), isTrue);
    await settings.save(s.copyWith(lastRetentionRunAt: null));
    expect((await settings.get()).lastRetentionRunAt, isNull);
  });

  test('events are filtered by time and keep every field', () async {
    final repo = DriftReminderEventRepository(db);
    final day = DateTime(2026, 10, 5);
    await repo.add(
      ReminderEvent(
        type: RoutineType.hydration,
        outcome: ReminderOutcome.done,
        at: day.subtract(const Duration(hours: 1)),
      ),
    );
    await repo.add(
      ReminderEvent(
        type: RoutineType.stretch,
        outcome: ReminderOutcome.snoozed,
        at: day.add(const Duration(hours: 10)),
        snoozedUntil: day.add(const Duration(hours: 10, minutes: 10)),
      ),
    );
    await repo.add(
      ReminderEvent(
        type: RoutineType.hydration,
        outcome: ReminderOutcome.done,
        at: day.add(const Duration(hours: 11)),
        waterMl: 250,
      ),
    );

    final today = await repo.getSince(day);
    expect(today.map((e) => e.type), [RoutineType.stretch, RoutineType.hydration]);
    expect(today.first.snoozedUntil, day.add(const Duration(hours: 10, minutes: 10)));
    expect(today.last.waterMl, 250);
  });

  test('event delete removes one event by id, ignores unknown ids, and streams', () async {
    final repo = DriftReminderEventRepository(db);
    final day = DateTime(2026, 10, 5, 10);
    final first = await repo.add(
      ReminderEvent(type: RoutineType.hydration, outcome: ReminderOutcome.done, at: day, waterMl: 500),
    );
    await repo.add(ReminderEvent(type: RoutineType.hydration, outcome: ReminderOutcome.done, at: day, waterMl: 150));
    final emissions = <List<int?>>[];
    final sub = repo.watchSince(day).listen((l) => emissions.add(l.map((e) => e.waterMl).toList()));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await repo.delete(first);
    await repo.delete(first);
    await repo.delete(999);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(emissions.first, [500, 150]);
    expect(emissions.last, [150]);
  });

  test('event deleteBefore removes only events strictly before the cutoff', () async {
    final repo = DriftReminderEventRepository(db);
    final cutoff = DateTime.utc(2026, 7, 10);
    for (final at in [
      cutoff.subtract(const Duration(days: 3)),
      cutoff.subtract(const Duration(milliseconds: 1)),
      cutoff,
      cutoff.add(const Duration(hours: 1)),
    ]) {
      await repo.add(ReminderEvent(type: RoutineType.stretch, outcome: ReminderOutcome.done, at: at));
    }
    expect(await repo.deleteBefore(cutoff), 2);
    expect((await repo.getSince(DateTime.utc(2000))).map((e) => e.at.isBefore(cutoff)), [false, false]);
    expect(await repo.deleteBefore(cutoff), 0);
  });

  test('work schedule save replaces all windows', () async {
    final repo = DriftWorkScheduleRepository(db);
    final split = WorkSchedule(
      days: {
        DateTime.sunday: [TimeWindow.hm(9, 0, 12, 0), TimeWindow.hm(13, 0, 17, 0)],
      },
    );
    await repo.save(split);
    expect(await repo.get(), split);
  });
}
