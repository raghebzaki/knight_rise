import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:knight_rise/core/database/app_database.steps.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/work_hours/domain/entities/work_schedule.dart';

part 'app_database.g.dart';

@DataClassName('RoutineRow')
class Routines extends Table {
  TextColumn get type => textEnum<RoutineType>()();
  IntColumn get intervalMinutes => integer()();
  IntColumn get dailyTarget => integer()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get mode => textEnum<ScheduleMode>()();

  @override
  Set<Column<Object>> get primaryKey => {type};
}

@DataClassName('WorkWindowRow')
class WorkWindows extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// ISO weekday, 1 = Monday … 7 = Sunday.
  IntColumn get weekday => integer()();
  IntColumn get startMinute => integer()();
  IntColumn get endMinute => integer()();
}

@DataClassName('ReminderEventRow')
@TableIndex(name: 'idx_events_at', columns: {#at})
@TableIndex(name: 'idx_events_type_at', columns: {#routineType, #at})
class ReminderEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get routineType => textEnum<RoutineType>()();
  TextColumn get outcome => text()();
  DateTimeColumn get at => dateTime()();
  DateTimeColumn get scheduledAt => dateTime().nullable()();
  DateTimeColumn get snoozedUntil => dateTime().nullable()();
  IntColumn get waterMl => integer().nullable()();
}

/// Single-row settings table (id is always 1). Lives in the database, not
/// SharedPreferences, so background isolates never read a stale cache.
@DataClassName('SettingsRow')
class AppSettingsTable extends Table {
  @override
  String get tableName => 'app_settings';

  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get themeVariant => text().withDefault(const Constant('midnight'))();
  BoolColumn get precisionTiming => boolean().withDefault(const Constant(false))();
  IntColumn get waterPerTapMl => integer().withDefault(const Constant(250))();

  /// IANA id the schedule was last reconciled in (null until first resume check).
  TextColumn get timezoneId => text().nullable()();

  /// False until the onboarding flow finishes. Upgraded installs are set to
  /// true in `from2To3` so existing users skip onboarding.
  BoolColumn get onboardingCompleted => boolean().withDefault(const Constant(false))();

  /// Send a single "Shield down" summary reminder when a Shield ends.
  BoolColumn get shieldRecoverOnExit => boolean().withDefault(const Constant(true))();

  /// A work day counts toward the streak when every enabled routine reaches
  /// this percentage of its daily target.
  IntColumn get streakThresholdPercent => integer().withDefault(const Constant(70))();

  /// Last time the 90-day retention job ran; it runs at most once a day.
  DateTimeColumn get lastRetentionRunAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Shield (focus / meeting) sessions. `end_at` is the planned end; `ended_at`
/// is set when the user ends the session early.
@DataClassName('ShieldSessionRow')
@TableIndex(name: 'idx_shield_sessions_end_at', columns: {#endAt})
class ShieldSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();

  /// `ShieldReason.name`.
  TextColumn get reason => text()();
}

/// Per-date work-hours overrides ("day off", "working late").
@DataClassName('DayOverrideRow')
class DayOverrides extends Table {
  /// Local date, `YYYY-MM-DD`.
  TextColumn get date => text()();

  /// `DayOverrideKind.name`: `off` | `extend`.
  TextColumn get kind => text()();
  IntColumn get extendMinutes => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {date};
}

/// Audit log of schedule reconciles (diagnostics screen, Milestone 3).
@DataClassName('ReconcileRunRow')
@TableIndex(name: 'idx_reconcile_runs_at', columns: {#at})
class ReconcileRuns extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get at => dateTime()();

  /// `ReconcileTrigger.name`.
  TextColumn get trigger => text()();
  IntColumn get planned => integer()();
  IntColumn get added => integer()();
  IntColumn get cancelled => integer()();
  TextColumn get error => text().nullable()();
}

/// One finalized past day (Milestone 4). Today is never stored: it is
/// computed live from reminder events. Kept permanently; powers streaks and
/// history charts after raw events are pruned.
@DataClassName('DailySummaryRow')
class DailySummaries extends Table {
  /// Local date, `YYYY-MM-DD`.
  TextColumn get date => text()();
  BoolColumn get isWorkDay => boolean()();
  IntColumn get waterMl => integer()();
  IntColumn get waterTargetMl => integer()();
  IntColumn get focusMinutes => integer()();

  /// Streak threshold in force when the day was finalized.
  IntColumn get thresholdPercent => integer()();
  BoolColumn get qualified => boolean()();
  DateTimeColumn get finalizedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {date};
}

/// Per-routine counts of a [DailySummaries] day, with the target and enabled
/// flag as they were that day.
@DataClassName('DailyRoutineSummaryRow')
class DailyRoutineSummaries extends Table {
  TextColumn get date => text().references(DailySummaries, #date, onDelete: KeyAction.cascade)();
  TextColumn get routineType => textEnum<RoutineType>()();
  IntColumn get done => integer()();
  IntColumn get target => integer()();
  BoolColumn get enabled => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {date, routineType};
}

@DriftDatabase(
  tables: [
    Routines,
    WorkWindows,
    ReminderEvents,
    AppSettingsTable,
    ReconcileRuns,
    ShieldSessions,
    DayOverrides,
    DailySummaries,
    DailyRoutineSummaries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Production database. `shareAcrossIsolates` makes the UI isolate and the
  /// notification / workmanager isolates talk to one drift server, found via
  /// IsolateNameServer, so concurrent writes are safe (Milestone 2).
  factory AppDatabase.open() =>
      AppDatabase(driftDatabase(name: 'knight_rise', native: const DriftNativeOptions(shareAcrossIsolates: true)));

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await seedDefaults();
    },
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        await m.addColumn(schema.appSettings, schema.appSettings.timezoneId);
        await m.createTable(schema.reconcileRuns);
        await m.createIndex(schema.idxReconcileRunsAt);
      },
      from2To3: (m, schema) async {
        await m.addColumn(schema.appSettings, schema.appSettings.onboardingCompleted);
        await m.addColumn(schema.appSettings, schema.appSettings.shieldRecoverOnExit);
        // Upgraded installs already know the app: skip onboarding.
        await customStatement('UPDATE app_settings SET onboarding_completed = 1');
        await m.createTable(schema.shieldSessions);
        await m.createIndex(schema.idxShieldSessionsEndAt);
        await m.createTable(schema.dayOverrides);
      },
      from3To4: (m, schema) async {
        await m.addColumn(schema.appSettings, schema.appSettings.streakThresholdPercent);
        await m.addColumn(schema.appSettings, schema.appSettings.lastRetentionRunAt);
        await m.createTable(schema.dailySummaries);
        await m.createTable(schema.dailyRoutineSummaries);
      },
    ),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Default routines, Sun–Thu 09:00–17:00, default settings.
  Future<void> seedDefaults() => batch((b) {
    b
      ..insertAll(routines, [
        for (final r in Routine.defaults)
          RoutinesCompanion.insert(
            type: r.type,
            intervalMinutes: r.intervalMinutes,
            dailyTarget: r.dailyTarget,
            enabled: Value(r.enabled),
            mode: r.mode,
          ),
      ])
      ..insertAll(workWindows, [
        for (final MapEntry(key: day, value: windows) in WorkSchedule.standard().days.entries)
          for (final w in windows)
            WorkWindowsCompanion.insert(weekday: day, startMinute: w.startMinute, endMinute: w.endMinute),
      ])
      ..insert(appSettingsTable, const AppSettingsTableCompanion());
  });
}
