import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/day_override_repository.dart';

@LazySingleton(as: DayOverrideRepository)
class DriftDayOverrideRepository implements DayOverrideRepository {
  const DriftDayOverrideRepository(this._db);
  final AppDatabase _db;

  /// ISO `YYYY-MM-DD` keys sort chronologically as text.
  SimpleSelectStatement<$DayOverridesTable, DayOverrideRow> _from(DateTime date) => _db.select(_db.dayOverrides)
    ..where((o) => o.date.isBiggerOrEqualValue(dateKey(date)))
    ..orderBy([(o) => OrderingTerm.asc(o.date)]);

  @override
  Stream<List<DayOverride>> watchFrom(DateTime date) => _from(date).watch().map((r) => r.map(_toDomain).toList());

  @override
  Future<List<DayOverride>> getFrom(DateTime date) => _from(date).get().then((r) => r.map(_toDomain).toList());

  @override
  Future<void> set(DayOverride o) => _db
      .into(_db.dayOverrides)
      .insertOnConflictUpdate(
        DayOverridesCompanion.insert(date: dateKey(o.date), kind: o.kind.name, extendMinutes: Value(o.extendMinutes)),
      );

  @override
  Future<void> clear(DateTime date) =>
      (_db.delete(_db.dayOverrides)..where((o) => o.date.equals(dateKey(date)))).go().then((_) {});

  static DayOverride _toDomain(DayOverrideRow r) => DayOverride(
    date: parseDateKey(r.date),
    kind: DayOverrideKind.values.asNameMap()[r.kind] ?? DayOverrideKind.off,
    extendMinutes: r.extendMinutes,
  );
}
