import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/scheduler/domain/repositories/reminder_event_repository.dart';

@LazySingleton(as: ReminderEventRepository)
class DriftReminderEventRepository implements ReminderEventRepository {
  const DriftReminderEventRepository(this._db);
  final AppDatabase _db;

  SimpleSelectStatement<$ReminderEventsTable, ReminderEventRow> _since(DateTime since) => _db.select(_db.reminderEvents)
    ..where((e) => e.at.isBiggerOrEqualValue(since))
    ..orderBy([(e) => OrderingTerm.asc(e.at), (e) => OrderingTerm.asc(e.id)]);

  @override
  Stream<List<ReminderEvent>> watchSince(DateTime since) => _since(since).watch().map((r) => r.map(_toDomain).toList());

  @override
  Future<List<ReminderEvent>> getSince(DateTime since) => _since(since).get().then((r) => r.map(_toDomain).toList());

  @override
  Future<int> add(ReminderEvent e) => _db
      .into(_db.reminderEvents)
      .insert(
        ReminderEventsCompanion.insert(
          routineType: e.type,
          outcome: e.outcome.name,
          at: e.at,
          scheduledAt: Value(e.scheduledAt),
          snoozedUntil: Value(e.snoozedUntil),
          waterMl: Value(e.waterMl),
        ),
      );

  static ReminderEvent _toDomain(ReminderEventRow r) => ReminderEvent(
    id: r.id,
    type: r.routineType,
    outcome: ReminderOutcome.values.byName(r.outcome),
    at: r.at,
    scheduledAt: r.scheduledAt,
    snoozedUntil: r.snoozedUntil,
    waterMl: r.waterMl,
  );
}
