import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/features/quest_log/data/drift_daily_summary_repository.dart';
import 'package:knight_rise/features/quest_log/domain/services/day_summarizer.dart';
import 'package:knight_rise/features/quest_log/domain/usecases/history_usecases.dart';
import 'package:knight_rise/features/routines/data/drift_routine_repository.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/data/drift_reminder_event_repository.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/settings/data/drift_settings_repository.dart';
import 'package:knight_rise/features/shield/data/drift_shield_repository.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';
import 'package:knight_rise/features/work_hours/data/drift_day_override_repository.dart';
import 'package:knight_rise/features/work_hours/data/drift_work_schedule_repository.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fakes.dart';
import '../../helpers/tz.dart';

void main() {
  late AppDatabase db;
  late FixedClock clock;
  late FakeLocationProvider location;
  late DriftDailySummaryRepository summaries;
  late DriftReminderEventRepository events;
  late DriftShieldRepository shields;
  late DriftDayOverrideRepository overrides;
  late DriftSettingsRepository settings;
  late DriftRoutineRepository routines;
  late FinalizeDays finalize;
  late PruneHistory prune;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    // Wednesday 2026-10-14, 08:00 Cairo.
    clock = FixedClock(at(cairo, 2026, 10, 14, 8));
    location = FakeLocationProvider(cairo);
    summaries = DriftDailySummaryRepository(db);
    events = DriftReminderEventRepository(db);
    shields = DriftShieldRepository(db);
    overrides = DriftDayOverrideRepository(db);
    settings = DriftSettingsRepository(db);
    routines = DriftRoutineRepository(db);
    finalize = FinalizeDays(
      summaries,
      routines,
      DriftWorkScheduleRepository(db),
      settings,
      events,
      shields,
      overrides,
      clock,
      location,
      const DaySummarizer(),
    );
    prune = PruneHistory(settings, events, shields, overrides, clock, location);
  });
  tearDown(() => db.close());

  DateTime d(int month, int day) => DateTime.utc(2026, month, day);

  Future<void> doneAt(DateTime t, [RoutineType type = RoutineType.stretch]) => events.add(
    ReminderEvent(
      type: type,
      outcome: ReminderOutcome.done,
      at: t,
      waterMl: type == RoutineType.hydration ? 250 : null,
    ),
  );

  Future<List<DateTime>> storedDates() async => [for (final s in await summaries.getFrom(d(1, 1))) s.date];

  group('FinalizeDays', () {
    test('nothing recorded yet: writes nothing', () async {
      expect(await finalize(), 0);
      expect(await storedDates(), isEmpty);
    });

    test('history starts at the first recorded activity and stops before today', () async {
      await doneAt(at(cairo, 2026, 10, 11, 10));
      await doneAt(at(cairo, 2026, 10, 14, 7)); // today: not finalized
      expect(await finalize(), 3);
      expect(await storedDates(), [d(10, 11), d(10, 12), d(10, 13)]);
      final first = (await summaries.getFrom(d(10, 11))).first;
      expect(first.routines[1].done, 1);
      expect(first.finalizedAt.isAtSameMomentAs(clock.now()), isTrue);
    });

    test('a Shield alone also starts the history', () async {
      await shields.add(
        ShieldSession(
          startAt: at(cairo, 2026, 10, 12, 10),
          endAt: at(cairo, 2026, 10, 12, 11),
          reason: ShieldReason.focus,
        ),
      );
      expect(await finalize(), 2);
      expect((await summaries.getFrom(d(10, 12))).first.focusMinutes, 60);
    });

    test('activity only today: nothing to finalize yet', () async {
      await doneAt(at(cairo, 2026, 10, 14, 7));
      expect(await finalize(), 0);
    });

    test('is idempotent: a second run writes nothing', () async {
      await doneAt(at(cairo, 2026, 10, 12, 10));
      expect(await finalize(), 2);
      expect(await finalize(), 0);
      expect(await storedDates(), [d(10, 12), d(10, 13)]);
    });

    test('catches up every day since the latest summary, including empty and rest days', () async {
      await doneAt(at(cairo, 2026, 10, 2, 10));
      clock.current = at(cairo, 2026, 10, 4, 1);
      expect(await finalize(), 2); // 2nd, 3rd
      clock.current = at(cairo, 2026, 10, 14, 8); // app not opened for 10 days
      expect(await finalize(), 10);
      final all = await summaries.getFrom(d(1, 1));
      expect(all.map((s) => s.date.day), [for (var i = 2; i <= 13; i++) i]);
      // Fri 9th and Sat 10th are rest days in the standard schedule.
      expect(all.where((s) => !s.isWorkDay).map((s) => s.date.day), [2, 3, 9, 10]);
    });

    test('concurrent calls in one isolate are coalesced', () async {
      await doneAt(at(cairo, 2026, 10, 12, 10));
      final results = await Future.wait([finalize(), finalize()]);
      expect(results, [2, 2]);
      expect(await storedDates(), [d(10, 12), d(10, 13)]);
    });

    test('looks back at most 90 days, even after a long absence', () async {
      await doneAt(at(cairo, 2026, 5, 1, 10));
      clock.current = at(cairo, 2026, 5, 2, 8);
      expect(await finalize(), 1);
      clock.current = at(cairo, 2026, 10, 14, 8);
      expect(await finalize(), kRetentionDays);
      final dates = await storedDates();
      expect(dates[1], d(7, 16)); // 14 Oct − 90 days
      expect(dates.last, d(10, 13));
    });

    test('a first run ignores activity older than 90 days', () async {
      await doneAt(at(cairo, 2026, 3, 1, 10));
      expect(await finalize(), 0);
      await doneAt(at(cairo, 2026, 8, 1, 10));
      await finalize();
      expect((await storedDates()).first, d(8, 1));
    });

    test('summarizes with the day override, threshold and routine targets', () async {
      await doneAt(at(cairo, 2026, 10, 12, 10));
      await overrides.set(DayOverride(date: d(10, 13), kind: DayOverrideKind.off));
      await settings.save((await settings.get()).copyWith(streakThresholdPercent: 50));
      await routines.save(Routine.defaults[1].copyWith(dailyTarget: 2));
      await finalize();
      final all = await summaries.getFrom(d(1, 1));
      expect(all.map((s) => (s.date.day, s.isWorkDay, s.thresholdPercent)), [(12, true, 50), (13, false, 50)]);
      expect(all.first.routines[1].target, 2);
    });

    test('day boundaries follow the current location', () async {
      // 23:30 UTC on the 12th is 02:30 on the 13th in Cairo (UTC+3 in October).
      await doneAt(DateTime.utc(2026, 10, 12, 23, 30));
      await finalize();
      expect(await storedDates(), [d(10, 13)]);
    });
  });

  group('PruneHistory', () {
    test('deletes raw data before today − 90 days and records the run', () async {
      final cutoff = at(cairo, 2026, 7, 16);
      await doneAt(cutoff.subtract(const Duration(minutes: 1)));
      await doneAt(cutoff);
      await shields.add(
        ShieldSession(
          startAt: at(cairo, 2026, 7, 15, 9),
          endAt: at(cairo, 2026, 7, 15, 10),
          reason: ShieldReason.focus,
        ),
      );
      await shields.add(
        ShieldSession(
          startAt: at(cairo, 2026, 7, 15, 23),
          endAt: at(cairo, 2026, 7, 16, 1),
          reason: ShieldReason.focus,
        ),
      );
      await overrides.set(DayOverride(date: d(7, 15), kind: DayOverrideKind.off));
      await overrides.set(DayOverride(date: d(7, 16), kind: DayOverrideKind.off));

      expect(await prune(), isTrue);
      expect((await events.getSince(DateTime.utc(2000))).map((e) => e.at.isAtSameMomentAs(cutoff)), [true]);
      expect((await shields.getSince(DateTime.utc(2000))).map((s) => s.id), [2]);
      expect((await overrides.getFrom(d(1, 1))).map((o) => o.date), [d(7, 16)]);
      expect((await settings.get()).lastRetentionRunAt!.isAtSameMomentAs(clock.now()), isTrue);
    });

    test('runs at most once per local day', () async {
      expect(await prune(), isTrue);
      clock.advance(const Duration(hours: 15)); // 23:00, same day
      expect(await prune(), isFalse);
      clock.advance(const Duration(hours: 1)); // midnight: a new day
      expect(await prune(), isTrue);
    });

    test('never deletes summaries', () async {
      await doneAt(at(cairo, 2026, 5, 1, 10));
      clock.current = at(cairo, 2026, 5, 2, 8);
      await finalize();
      clock.current = at(cairo, 2026, 10, 14, 8);
      await prune();
      expect(await storedDates(), [d(5, 1)]);
      expect(await events.getSince(DateTime.utc(2000)), isEmpty);
    });
  });

  group('MaintainHistory', () {
    test('finalizes before pruning, so the oldest kept day is summarized first', () async {
      // Last summary was written on 15 Jul; the app then stays closed.
      await doneAt(at(cairo, 2026, 7, 14, 10));
      clock.current = at(cairo, 2026, 7, 15, 8);
      await finalize();
      await doneAt(at(cairo, 2026, 7, 16, 10));
      clock.current = at(cairo, 2026, 10, 14, 8);

      await MaintainHistory(finalize, prune)();

      final all = await summaries.getFrom(d(1, 1));
      expect(all.first.date, d(7, 14));
      final kept = all.firstWhere((s) => s.date == d(7, 16));
      expect(kept.routines[1].done, 1);
      expect((await events.getSince(DateTime.utc(2000))).length, 1);
    });

    test('skips pruning when finalizing throws', () async {
      final failing = _MockFinalizeDays();
      when(failing.call).thenThrow(StateError('db closed'));
      await expectLater(MaintainHistory(failing, prune)(), throwsStateError);
      expect((await settings.get()).lastRetentionRunAt, isNull);
    });
  });
}

class _MockFinalizeDays extends Mock implements FinalizeDays;
