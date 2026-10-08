import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';
import 'package:knight_rise/features/shield/domain/repositories/shield_repository.dart';

@LazySingleton(as: ShieldRepository)
class DriftShieldRepository implements ShieldRepository {
  const DriftShieldRepository(this._db);
  final AppDatabase _db;

  /// `effectiveEnd <= endAt`, so `endAt > since` is a safe, index-backed
  /// pre-filter; the exact `effectiveEnd > since` check happens in Dart.
  SimpleSelectStatement<$ShieldSessionsTable, ShieldSessionRow> _since(DateTime since) => _db.select(_db.shieldSessions)
    ..where((s) => s.endAt.isBiggerThanValue(since))
    ..orderBy([(s) => OrderingTerm.asc(s.startAt), (s) => OrderingTerm.asc(s.id)]);

  static List<ShieldSession> _filter(List<ShieldSessionRow> rows, DateTime since) => [
    for (final r in rows)
      if (_toDomain(r).effectiveEnd.isAfter(since)) _toDomain(r),
  ];

  @override
  Stream<List<ShieldSession>> watchSince(DateTime since) => _since(since).watch().map((r) => _filter(r, since));

  @override
  Future<List<ShieldSession>> getSince(DateTime since) => _since(since).get().then((r) => _filter(r, since));

  @override
  Future<int> add(ShieldSession s) => _db
      .into(_db.shieldSessions)
      .insert(
        ShieldSessionsCompanion.insert(
          startAt: s.startAt,
          endAt: s.endAt,
          endedAt: Value(s.endedAt),
          reason: s.reason.name,
        ),
      );

  @override
  Future<void> update(ShieldSession s) async {
    final id = s.id;
    if (id == null) throw ArgumentError.value(s, 'session', 'Cannot update a session without an id');
    await (_db.update(_db.shieldSessions)..where((r) => r.id.equals(id))).write(
      ShieldSessionsCompanion(
        startAt: Value(s.startAt),
        endAt: Value(s.endAt),
        endedAt: Value(s.endedAt),
        reason: Value(s.reason.name),
      ),
    );
  }

  @override
  Future<ShieldSession?> active(DateTime now) async {
    final rows =
        await (_db.select(_db.shieldSessions)
              ..where((s) => s.startAt.isSmallerOrEqualValue(now) & s.endAt.isBiggerThanValue(now))
              ..orderBy([(s) => OrderingTerm.desc(s.startAt), (s) => OrderingTerm.desc(s.id)]))
            .get();
    return rows.map(_toDomain).where((s) => s.isActiveAt(now)).firstOrNull;
  }

  @override
  Future<int> deleteEndedBefore(DateTime cutoff) =>
      (_db.delete(_db.shieldSessions)..where((s) => s.endAt.isSmallerThanValue(cutoff))).go();

  static ShieldSession _toDomain(ShieldSessionRow r) => ShieldSession(
    id: r.id,
    startAt: r.startAt,
    endAt: r.endAt,
    endedAt: r.endedAt,
    reason: ShieldReason.values.asNameMap()[r.reason] ?? ShieldReason.custom,
  );
}
