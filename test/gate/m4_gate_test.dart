// Milestone 4 gate: history, streaks and retention end to end.
//
// Everything below the OS boundary is real: Drift (in memory, or a shared
// drift isolate server for the cross-isolate scenario), the Drift
// repositories, the real use cases (Done / Snooze through
// HandleReminderAction, CompleteRoutine / UndoCompletion, FinalizeDays,
// PruneHistory, MaintainHistory), ReconcileSchedule + ReminderPlanner, the
// DaySummarizer and StreakCalculator, and the Quest Log cubit. Only the clock
// (FixedClock, Cairo) and the notification scheduler (OsNotificationSimulator)
// are simulated.
//
// Defaults: Sun–Thu 09:00–17:00; hydration 8 × 250 ml (2,000 ml), stretch 6,
// eye rest 12; streak goal 70 %; 90-day retention.
import 'dart:isolate';

import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/quest_log/data/drift_daily_summary_repository.dart';
import 'package:knight_rise/features/quest_log/domain/entities/daily_summary.dart';
import 'package:knight_rise/features/quest_log/domain/services/day_summarizer.dart';
import 'package:knight_rise/features/quest_log/domain/services/history_series.dart';
import 'package:knight_rise/features/quest_log/domain/services/streak_calculator.dart';
import 'package:knight_rise/features/quest_log/domain/usecases/history_usecases.dart';
import 'package:knight_rise/features/quest_log/presentation/quest_log_cubit.dart';
import 'package:knight_rise/features/routines/data/drift_routine_repository.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/data/background_tasks.dart';
import 'package:knight_rise/features/scheduler/data/drift_reconcile_run_repository.dart';
import 'package:knight_rise/features/scheduler/data/drift_reminder_event_repository.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/handle_reminder_action.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/reconcile_schedule.dart';
import 'package:knight_rise/features/settings/data/drift_settings_repository.dart';
import 'package:knight_rise/features/shield/data/drift_shield_repository.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:knight_rise/features/work_hours/data/drift_day_override_repository.dart';
import 'package:knight_rise/features/work_hours/data/drift_work_schedule_repository.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';
import 'package:timezone/timezone.dart' as tz;

import '../drift/knight_db/generated/schema.dart';
import '../drift/knight_db/generated/schema_v3.dart' as v3;
import '../helpers/fakes.dart';
import '../helpers/tz.dart';
import 'os_simulator.dart';

tz.TZDateTime t(int month, int day, [int h = 0, int m = 0]) => tz.TZDateTime(cairo, 2026, month, day, h, m);
DateTime d(int month, int day) => DateTime.utc(2026, month, day);

/// The app below the OS, wired as production wires it, on [db].
class M4Gate {
  M4Gate(this.db, this.clock) : os = OsNotificationSimulator(clock) {
    routines = DriftRoutineRepository(db);
    work = DriftWorkScheduleRepository(db);
    settings = DriftSettingsRepository(db);
    events = DriftReminderEventRepository(db);
    shields = DriftShieldRepository(db);
    overrides = DriftDayOverrideRepository(db);
    summaries = DriftDailySummaryRepository(db);
    final location = FakeLocationProvider(cairo);
    reconciler = ReconcileSchedule(
      routines,
      work,
      settings,
      events,
      shields,
      overrides,
      DriftReconcileRunRepository(db),
      os,
      const ReminderPlanner(),
      clock,
      location,
    );
    complete = CompleteRoutine(events, settings, clock);
    handle = HandleReminderAction(complete, SnoozeRoutine(events, clock, cairo), reconciler, EndShield(shields, clock));
    finalize = FinalizeDays(
      summaries,
      routines,
      work,
      settings,
      events,
      shields,
      overrides,
      clock,
      location,
      const DaySummarizer(),
    );
    prune = PruneHistory(settings, events, shields, overrides, clock, location);
    maintain = MaintainHistory(finalize, prune);
    watchInputs = WatchCycleInputs(routines, work, events, settings, shields, overrides);
    undo = UndoCompletion(events);
    this.location = location;
  }

  factory M4Gate.memory(tz.TZDateTime start) => M4Gate(AppDatabase(NativeDatabase.memory()), FixedClock(start));

  final AppDatabase db;
  final FixedClock clock;
  final OsNotificationSimulator os;
  late final FakeLocationProvider location;
  late final DriftRoutineRepository routines;
  late final DriftWorkScheduleRepository work;
  late final DriftSettingsRepository settings;
  late final DriftReminderEventRepository events;
  late final DriftShieldRepository shields;
  late final DriftDayOverrideRepository overrides;
  late final DriftDailySummaryRepository summaries;
  late final ReconcileSchedule reconciler;
  late final CompleteRoutine complete;
  late final UndoCompletion undo;
  late final HandleReminderAction handle;
  late final FinalizeDays finalize;
  late final PruneHistory prune;
  late final MaintainHistory maintain;
  late final WatchCycleInputs watchInputs;

  Future<void> close() => db.close();

  /// Launch or resume: production runs MaintainHistory (and a reconcile).
  Future<void> openAppAt(tz.TZDateTime at) async {
    clock.current = at;
    await maintain();
  }

  /// Completes [share] of each enabled routine's target on [day] (from 10:00,
  /// one minute apart), as in-app taps. Hydration logs 250 ml per tap.
  Future<void> workDay(int month, int day, {double share = 1}) async {
    var minute = 0;
    for (final r in await routines.getAll()) {
      if (!r.enabled) continue;
      final n = (r.dailyTarget * share).ceil();
      for (var i = 0; i < n; i++) {
        clock.current = t(month, day, 10).add(Duration(minutes: minute++));
        await complete(r.type);
      }
    }
  }

  Future<List<DailySummary>> allSummaries() => summaries.getFrom(DateTime.utc(1970));

  Future<StreakStatus> streak() async {
    final now = clock.now();
    final day = localDateOf(now, cairo);
    final today = const DaySummarizer()(
      SummaryInputs(
        routines: await routines.getAll(),
        schedule: await work.get(),
        settings: await settings.get(),
        events: await events.getSince(startOfDate(day, cairo)),
        shields: await shields.getSince(startOfDate(day, cairo)),
        overrides: await overrides.getFrom(day),
      ),
      date: day,
      location: cairo,
      at: now,
    );
    return const StreakCalculator()(await allSummaries(), today: day, todaySummary: today);
  }

  QuestLogCubit questLog() => QuestLogCubit(
    watchInputs,
    summaries,
    const DaySummarizer(),
    const StreakCalculator(),
    complete,
    undo,
    maintain,
    clock,
    location,
  );

  Future<List<String>> pending() async => [
    for (final p in await os.pendingReminders())
      if (p.payload != null)
        '${tz.TZDateTime.from(p.payload!.fireAt, cairo)} ${p.payload!.types.map((t) => t.name).join('+')}',
  ];
}

/// The cubit's current state if it already matches [test], else the next
/// matching one (an update can land while the test awaits something else).
Future<QuestLogState> until(QuestLogCubit cubit, bool Function(QuestLogState s) test) =>
    test(cubit.state) ? Future.value(cubit.state) : cubit.stream.firstWhere(test);

// ------------------------------------------------- cross-isolate helpers

/// Opener for the shared drift server (runs on its own isolate).
DatabaseConnection _openShared() => DatabaseConnection(NativeDatabase.memory());

/// What a notification action handler does in the background isolate: open
/// its own connection to the shared server and mark [type] done at [atMs].
Future<int> _backgroundDone(DriftIsolate server, String type, int atMs) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = AppDatabase(await server.connect());
  final clock = FixedClock(DateTime.fromMillisecondsSinceEpoch(atMs));
  final id = await CompleteRoutine(DriftReminderEventRepository(db), DriftSettingsRepository(db), clock)(
    RoutineType.values.byName(type),
  );
  await db.close();
  return id;
}

/// The WorkManager task in its headless isolate: reconcile, then finalize and
/// prune history, on its own connection to the shared server.
Future<bool> _backgroundPeriodicTask(DriftIsolate server, int atMs) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = AppDatabase(await server.connect());
  final gate = M4Gate(db, FixedClock(DateTime.fromMillisecondsSinceEpoch(atMs)));
  final ok = await runBackgroundTask(
    'periodic',
    bootstrap: () async {},
    reconciler: () async => gate.reconciler,
    maintainHistory: gate.maintain.call,
  );
  await db.close();
  return ok;
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('G1 catch-up: a week with the app closed is finalized on the next open, rest days included', () async {
    final g = M4Gate.memory(t(10, 1, 8)); // Thu 1 Oct
    addTearDown(g.close);
    await g.workDay(10, 1);
    await g.openAppAt(t(10, 1, 18)); // same day: nothing to finalize yet
    expect(await g.allSummaries(), isEmpty);

    await g.openAppAt(t(10, 8, 9)); // Thu 8 Oct
    final all = await g.allSummaries();
    expect(all.map((s) => s.date.day), [1, 2, 3, 4, 5, 6, 7]);
    expect(all.map((s) => s.isWorkDay), [true, false, false, true, true, true, true]);
    expect(all.map((s) => s.qualified), [true, false, false, false, false, false, false]);
    expect(all.first.waterMl, 2000);
    expect(await g.streak(), const StreakStatus(current: 0, best: 1));

    // Idempotent: a resume and the background task find nothing new.
    expect(await g.finalize(), 0);
    expect(await g.allSummaries(), hasLength(7));

    // The 7-day chart (1–7 Oct) shows the same: five work days, one met.
    final week = buildHistorySeries(all, today: d(10, 8), range: HistoryRange.week);
    expect((week.stats.workDays, week.stats.goalDays), (5, 1));
  });

  test('G2 notifications only: answering every delivered reminder with Done qualifies the day', () async {
    final g = M4Gate.memory(t(10, 5, 8)); // Mon 5 Oct
    addTearDown(g.close);
    await g.reconciler.reconcile(ReconcileTrigger.launch);

    // Deliver and answer each reminder one minute after it fires, all day.
    var answered = 0;
    while (true) {
      final next = (await g.os.pendingReminders()).where((p) => p.payload != null).toList()
        ..sort((a, b) => a.payload!.fireAt.compareTo(b.payload!.fireAt));
      if (next.isEmpty || !next.first.payload!.fireAt.isBefore(t(10, 5, 17))) break;
      final (id, r) = (next.first.id, next.first.payload!);
      g.os.advanceTo(r.fireAt);
      g.clock.current = tz.TZDateTime.from(r.fireAt.add(const Duration(minutes: 1)), cairo);
      await g.handle(
        ReminderAction(kind: ReminderActionKind.done, types: r.types, scheduledAt: r.fireAt, notificationId: id),
      );
      answered++;
    }
    expect(answered, greaterThan(10));

    await g.openAppAt(t(10, 6, 8)); // Tue morning
    final monday = (await g.allSummaries()).single;
    expect(monday.date, d(10, 5));
    expect(monday.qualified, isTrue, reason: 'every enabled routine reached 70 % through notifications alone');
    for (final r in monday.routines) {
      expect(monday.measureOf(r).reaches(70), isTrue, reason: r.type.name);
    }
    final hydration = monday.routines.firstWhere((r) => r.type == RoutineType.hydration);
    expect(monday.waterMl, hydration.done * 250);
    expect((await g.streak()).current, 1);
  });

  test("G3 cross-isolate: a background Done shows up live and in the next day's summary", () async {
    final server = await DriftIsolate.spawn(_openShared);
    addTearDown(server.shutdownAll);
    final ui = M4Gate(AppDatabase(await server.connect()), FixedClock(t(10, 5, 9)));
    addTearDown(ui.close);

    final cubit = ui.questLog()..start();
    addTearDown(cubit.close);
    final first = await until(cubit, (s) => s.status == QuestLogStatus.ready);
    expect(first.view!.today.routines[1].done, 0);

    // A notification "Done" handled in another isolate.
    final atMs = t(10, 5, 10, 5).millisecondsSinceEpoch;
    await Isolate.run(() => _backgroundDone(server, 'stretch', atMs));
    final live = await until(cubit, (s) => s.view!.today.routines[1].done == 1);
    expect(live.view!.lastDoneAt[RoutineType.stretch]!.isAtSameMomentAs(t(10, 5, 10, 5)), isTrue);

    // The hourly background task after midnight finalizes Monday.
    final taskMs = t(10, 6, 0, 30).millisecondsSinceEpoch;
    expect(await Isolate.run(() => _backgroundPeriodicTask(server, taskMs)), isTrue);
    final monday = (await ui.allSummaries()).single;
    expect(monday.date, d(10, 5));
    expect(monday.routines[1].done, 1);
    expect((await ui.settings.get()).lastRetentionRunAt, isNotNull, reason: 'prune ran in the background too');
  });

  test('G4 retention: 120 days of daily use keep every summary but only 90 days of raw data', () async {
    final g = M4Gate.memory(t(6, 1, 8)); // Mon 1 Jun
    addTearDown(g.close);
    await g.overrides.set(DayOverride(date: d(6, 10), kind: DayOverrideKind.off)); // Wed 10 Jun off
    for (var day = DateTime.utc(2026, 6); day.isBefore(DateTime.utc(2026, 9, 29)); day = addDays(day, 1)) {
      final workDay = day.weekday != DateTime.friday && day.weekday != DateTime.saturday && day != d(6, 10);
      await g.openAppAt(t(day.month, day.day, 8));
      if (workDay) {
        await g.workDay(day.month, day.day);
        await g.shields.add(
          ShieldSession(
            startAt: t(day.month, day.day, 13),
            endAt: t(day.month, day.day, 13, 25),
            reason: ShieldReason.focus,
          ),
        );
      }
    }
    await g.openAppAt(t(9, 29, 8)); // Tue 29 Sep
    final cutoff = t(7, 1); // 29 Sep − 90 days

    final all = await g.allSummaries();
    expect(all.first.date, d(6, 1));
    expect(all.last.date, d(9, 28));
    expect(all, hasLength(120));
    expect(all.first.focusMinutes, 25, reason: 'summaries outlive their raw data');
    final june10 = all.firstWhere((s) => s.date == d(6, 10));
    expect(june10.isWorkDay, isFalse, reason: 'the day-off override is gone, its summary still says rest day');

    final rawEvents = await g.events.getSince(DateTime.utc(2000));
    expect(rawEvents.every((e) => !e.at.isBefore(cutoff)), isTrue);
    expect(rawEvents.first.at.isBefore(t(7, 3)), isTrue, reason: 'the 90 most recent days are kept');
    expect((await g.shields.getSince(DateTime.utc(2000))).every((s) => !s.endAt.isBefore(cutoff)), isTrue);
    expect(await g.overrides.getFrom(DateTime.utc(2000)), isEmpty);

    // Every work day qualified; rest days are neutral → one unbroken streak.
    final streak = await g.streak();
    expect(streak.current, all.where((s) => s.countsTowardStreak).length);
    expect(streak.best, streak.current);
    final month = buildHistorySeries(all, today: d(9, 29), range: HistoryRange.month);
    expect(month.stats.goalDays, month.stats.workDays);
  });

  test('G5 streaks: rest days and a day off are neutral; a raised goal applies from the next day on', () async {
    final g = M4Gate.memory(t(10, 4, 8)); // Sun 4 Oct
    addTearDown(g.close);
    await g.workDay(10, 4); // Sun 100 %
    await g.openAppAt(t(10, 5, 8));
    await g.workDay(10, 5, share: 0.8); // Mon 80 % (goal 70)
    await g.openAppAt(t(10, 6, 8));
    await g.workDay(10, 6); // Tue 100 %
    await g.overrides.set(DayOverride(date: d(10, 7), kind: DayOverrideKind.off)); // Wed off
    await g.openAppAt(t(10, 8, 8)); // Thu: Wed finalized with the 70 % goal…
    await g.settings.save((await g.settings.get()).copyWith(streakThresholdPercent: 90)); // …then raised
    expect((await g.streak()).current, 3);
    await g.workDay(10, 8, share: 0.8); // Thu 80 % < 90 %
    await g.openAppAt(t(10, 11, 8)); // Sun (Fri / Sat rest)

    final all = await g.allSummaries();
    expect(all.map((s) => (s.date.day, s.thresholdPercent, s.qualified)), [
      (4, 70, true),
      (5, 70, true), // 80 % kept its 70 % goal
      (6, 70, true),
      (7, 70, false), // day off: neutral
      (8, 90, false),
      (9, 90, false),
      (10, 90, false),
    ]);
    expect(all.firstWhere((s) => s.date == d(10, 7)).countsTowardStreak, isFalse);
    expect(await g.streak(), const StreakStatus(current: 0, best: 3));

    await g.workDay(10, 11); // Sun 100 % ≥ 90 %
    expect((await g.streak()).current, 1);
  });

  test('G6 water undo: the log and its schedule effect are fully reverted', () async {
    final g = M4Gate.memory(t(10, 5, 9, 50)); // Mon
    addTearDown(g.close);
    await g.reconciler.reconcile(ReconcileTrigger.launch);
    final before = await g.pending();

    final cubit = g.questLog()..start();
    addTearDown(cubit.close);
    await until(cubit, (s) => s.status == QuestLogStatus.ready);

    final kept = await cubit.logWater(250);
    final undone = await cubit.logWater(500);
    await g.reconciler.reconcile(ReconcileTrigger.action); // the sync service reacts to the events stream
    expect(await g.pending(), isNot(before), reason: 'rolling hydration moves after a completion');
    await cubit.undoWater(undone);
    await cubit.undoWater(kept);
    await g.reconciler.reconcile(ReconcileTrigger.action);
    expect(await g.pending(), before, reason: 'undoing every log restores the original schedule');

    await cubit.logWater(150);
    await g.openAppAt(t(10, 6, 8));
    final monday = (await g.allSummaries()).single;
    expect(monday.waterMl, 150);
    expect(monday.routines.first.done, 1);
  });

  test('G7 migration: an M3 database (v3) with live data upgrades and builds history', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(3);
    final old = v3.DatabaseAtV3(schema.newConnection());
    int s(tz.TZDateTime x) => x.millisecondsSinceEpoch ~/ 1000;
    await old.batch((b) {
      b
        ..insertAll(old.routines, [
          const v3.RoutinesData(type: 'hydration', intervalMinutes: 45, dailyTarget: 8, enabled: 1, mode: 'rolling'),
          const v3.RoutinesData(type: 'stretch', intervalMinutes: 60, dailyTarget: 4, enabled: 1, mode: 'rolling'),
          const v3.RoutinesData(type: 'eyeRest', intervalMinutes: 20, dailyTarget: 12, enabled: 0, mode: 'rolling'),
        ])
        ..insertAll(old.workWindows, [
          for (final day in [7, 1, 2, 3, 4])
            v3.WorkWindowsData(id: day, weekday: day, startMinute: 480, endMinute: 960),
        ])
        ..insertAll(old.appSettings, [
          const v3.AppSettingsData(
            id: 1,
            themeVariant: 'amoled',
            precisionTiming: 1,
            waterPerTapMl: 250,
            timezoneId: 'Africa/Cairo',
            onboardingCompleted: 1,
            shieldRecoverOnExit: 1,
          ),
        ])
        // Thu 1 Oct: hydration 6 × 250 ml (75 %) and stretch 3 / 4 (75 %).
        ..insertAll(old.reminderEvents, [
          for (var i = 0; i < 6; i++)
            v3.ReminderEventsData(
              id: i + 1,
              routineType: 'hydration',
              outcome: 'done',
              at: s(t(10, 1, 9 + i)),
              waterMl: 250,
            ),
          for (var i = 0; i < 3; i++)
            v3.ReminderEventsData(id: 10 + i, routineType: 'stretch', outcome: 'done', at: s(t(10, 1, 10 + i))),
        ])
        ..insertAll(old.shieldSessions, [
          v3.ShieldSessionsData(id: 1, startAt: s(t(10, 1, 14)), endAt: s(t(10, 1, 14, 50)), reason: 'meeting'),
        ])
        ..insertAll(old.dayOverrides, [const v3.DayOverridesData(date: '2026-10-06', kind: 'off')]);
    });
    await old.close();

    final g = M4Gate(AppDatabase(schema.newConnection()), FixedClock(t(10, 5, 7, 30))); // Mon, before work
    addTearDown(g.close);
    final settings = await g.settings.get();
    expect(settings.onboardingCompleted, isTrue);
    expect(settings.precisionTiming, isTrue);
    expect(settings.streakThresholdPercent, 70);
    expect(settings.hapticsEnabled, isTrue);

    await g.maintain();
    final all = await g.allSummaries();
    expect(all.map((x) => x.date.day), [1, 2, 3, 4], reason: 'history starts at the first M3 event');
    final thursday = all.first;
    expect(thursday.qualified, isTrue, reason: 'eye rest is disabled; hydration and stretch reached 75 %');
    expect(thursday.waterMl, 1500);
    expect(thursday.focusMinutes, 50);
    expect(thursday.routines.map((r) => (r.type, r.target, r.enabled)), [
      (RoutineType.hydration, 8, true),
      (RoutineType.stretch, 4, true),
      (RoutineType.eyeRest, 12, false),
    ]);
    expect(all.map((x) => x.isWorkDay), [true, false, false, true], reason: "M3's Sun–Thu 08–16 schedule");

    // The migrated schedule still plans from M3's work hours (eye rest off,
    // so the first reminder is hydration at 08:45)…
    Future<List<tz.TZDateTime>> fires() async =>
        [for (final p in await g.os.pendingReminders()) tz.TZDateTime.from(p.payload!.fireAt, cairo)]..sort();
    expect((await g.reconciler.reconcile(ReconcileTrigger.launch)).error, isNull);
    expect((await fires()).first, t(10, 5, 8, 45));

    // …and M3's "day off" for Tue 6 Oct still silences Tuesday: late Monday
    // the 24 h horizon reaches into Tuesday, yet nothing is planned there
    // until the override is cleared.
    g.clock.current = t(10, 5, 16, 30);
    await g.reconciler.reconcile(ReconcileTrigger.resume);
    expect(await fires(), isEmpty);
    await g.overrides.clear(d(10, 6));
    await g.reconciler.reconcile(ReconcileTrigger.configChange);
    expect((await fires()).first, t(10, 6, 8, 45));
  });
}
