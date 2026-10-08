import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/features/quest_log/domain/entities/daily_summary.dart';
import 'package:knight_rise/features/quest_log/domain/repositories/daily_summary_repository.dart';

@LazySingleton(as: DailySummaryRepository)
class DriftDailySummaryRepository implements DailySummaryRepository {
  const DriftDailySummaryRepository(this._db);
  final AppDatabase _db;

  /// ISO `YYYY-MM-DD` keys sort chronologically as text.
  Selectable<(DailySummaryRow, DailyRoutineSummaryRow?)> _from(DateTime date) {
    final s = _db.dailySummaries;
    final r = _db.dailyRoutineSummaries;
    return (_db.select(s).join([leftOuterJoin(r, r.date.equalsExp(s.date))])
          ..where(s.date.isBiggerOrEqualValue(dateKey(date)))
          ..orderBy([OrderingTerm.asc(s.date)]))
        .map((row) => (row.readTable(s), row.readTableOrNull(r)));
  }

  @override
  Stream<List<DailySummary>> watchFrom(DateTime date) => _from(date).watch().map(_group);

  @override
  Future<List<DailySummary>> getFrom(DateTime date) => _from(date).get().then(_group);

  @override
  Future<DateTime?> latestDate() async {
    final max = _db.dailySummaries.date.max();
    final key = await (_db.selectOnly(_db.dailySummaries)..addColumns([max])).map((r) => r.read(max)).getSingle();
    return key == null ? null : parseDateKey(key);
  }

  @override
  Future<void> upsert(DailySummary s) => _db.transaction(() async {
    final key = dateKey(s.date);
    await _db
        .into(_db.dailySummaries)
        .insertOnConflictUpdate(
          DailySummariesCompanion.insert(
            date: key,
            isWorkDay: s.isWorkDay,
            waterMl: s.waterMl,
            waterTargetMl: s.waterTargetMl,
            focusMinutes: s.focusMinutes,
            thresholdPercent: s.thresholdPercent,
            qualified: s.qualified,
            finalizedAt: s.finalizedAt,
          ),
        );
    await (_db.delete(_db.dailyRoutineSummaries)..where((r) => r.date.equals(key))).go();
    await _db.batch(
      (b) => b.insertAll(_db.dailyRoutineSummaries, [
        for (final r in s.routines)
          DailyRoutineSummariesCompanion.insert(
            date: key,
            routineType: r.type,
            done: r.done,
            target: r.target,
            enabled: r.enabled,
          ),
      ]),
    );
  });

  /// Folds the joined rows (one per routine, ordered by date) into summaries.
  static List<DailySummary> _group(List<(DailySummaryRow, DailyRoutineSummaryRow?)> rows) {
    final days = <String, (DailySummaryRow, List<RoutineDaySummary>)>{};
    for (final (day, routine) in rows) {
      final entry = days.putIfAbsent(day.date, () => (day, []));
      if (routine != null) entry.$2.add(_routineToDomain(routine));
    }
    return [for (final (day, routines) in days.values) _toDomain(day, routines)];
  }

  static DailySummary _toDomain(DailySummaryRow r, List<RoutineDaySummary> routines) => DailySummary(
    date: parseDateKey(r.date),
    isWorkDay: r.isWorkDay,
    waterMl: r.waterMl,
    waterTargetMl: r.waterTargetMl,
    focusMinutes: r.focusMinutes,
    thresholdPercent: r.thresholdPercent,
    qualified: r.qualified,
    finalizedAt: r.finalizedAt,
    routines: routines..sort((a, b) => a.type.index.compareTo(b.type.index)),
  );

  static RoutineDaySummary _routineToDomain(DailyRoutineSummaryRow r) =>
      RoutineDaySummary(type: r.routineType, done: r.done, target: r.target, enabled: r.enabled);
}
