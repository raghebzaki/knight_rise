import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/features/settings/domain/entities/app_settings.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';

@LazySingleton(as: SettingsRepository)
class DriftSettingsRepository implements SettingsRepository {
  const DriftSettingsRepository(this._db);
  final AppDatabase _db;

  SimpleSelectStatement<$AppSettingsTableTable, SettingsRow> get _query =>
      _db.select(_db.appSettingsTable)..where((s) => s.id.equals(1));

  @override
  Stream<AppSettings> watch() => _query.watchSingleOrNull().map(_toDomain);

  @override
  Future<AppSettings> get() => _query.getSingleOrNull().then(_toDomain);

  @override
  Future<void> save(AppSettings s) => _db
      .into(_db.appSettingsTable)
      .insertOnConflictUpdate(
        AppSettingsTableCompanion.insert(
          id: const Value(1),
          themeVariant: Value(s.themeVariant.name),
          precisionTiming: Value(s.precisionTiming),
          waterPerTapMl: Value(s.waterPerTapMl),
          timezoneId: Value(s.timezoneId),
          onboardingCompleted: Value(s.onboardingCompleted),
          shieldRecoverOnExit: Value(s.shieldRecoverOnExit),
          streakThresholdPercent: Value(s.streakThresholdPercent),
          lastRetentionRunAt: Value(s.lastRetentionRunAt),
          hapticsEnabled: Value(s.hapticsEnabled),
          rankCelebratedOn: Value(s.rankCelebratedOn == null ? null : dateKey(s.rankCelebratedOn!)),
          localeCode: Value(s.localeCode),
        ),
      );

  @override
  Future<void> markRetentionRun(DateTime at) => _db
      .into(_db.appSettingsTable)
      .insert(
        AppSettingsTableCompanion.insert(id: const Value(1), lastRetentionRunAt: Value(at)),
        onConflict: DoUpdate((_) => AppSettingsTableCompanion(lastRetentionRunAt: Value(at))),
      );

  @override
  Future<void> markRankCelebrated(DateTime date) => _db
      .into(_db.appSettingsTable)
      .insert(
        AppSettingsTableCompanion.insert(id: const Value(1), rankCelebratedOn: Value(dateKey(date))),
        onConflict: DoUpdate((_) => AppSettingsTableCompanion(rankCelebratedOn: Value(dateKey(date)))),
      );

  static AppSettings _toDomain(SettingsRow? r) => r == null
      ? const AppSettings()
      : AppSettings(
          themeVariant: ThemeVariant.values.asNameMap()[r.themeVariant] ?? ThemeVariant.midnight,
          precisionTiming: r.precisionTiming,
          waterPerTapMl: r.waterPerTapMl,
          timezoneId: r.timezoneId,
          onboardingCompleted: r.onboardingCompleted,
          shieldRecoverOnExit: r.shieldRecoverOnExit,
          streakThresholdPercent: r.streakThresholdPercent,
          lastRetentionRunAt: r.lastRetentionRunAt,
          hapticsEnabled: r.hapticsEnabled,
          rankCelebratedOn: r.rankCelebratedOn == null ? null : parseDateKey(r.rankCelebratedOn!),
          localeCode: r.localeCode,
        );
}
