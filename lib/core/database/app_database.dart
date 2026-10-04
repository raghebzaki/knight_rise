import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
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

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Routines, WorkWindows, ReminderEvents, AppSettingsTable])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Production database. `shareAcrossIsolates` makes the UI isolate and the
  /// notification / workmanager isolates talk to one drift server, found via
  /// IsolateNameServer, so concurrent writes are safe (Milestone 2).
  factory AppDatabase.open() =>
      AppDatabase(driftDatabase(name: 'knight_rise', native: const DriftNativeOptions(shareAcrossIsolates: true)));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await seedDefaults();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Default routines, Mon–Fri 09:00–17:00, default settings.
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
