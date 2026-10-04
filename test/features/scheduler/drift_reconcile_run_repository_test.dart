import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/features/scheduler/data/drift_reconcile_run_repository.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';

void main() {
  late AppDatabase db;
  late DriftReconcileRunRepository repo;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftReconcileRunRepository(db);
  });
  tearDown(() => db.close());

  final base = DateTime(2026, 10, 5, 9);
  ReconcileRun run(int minute, {ReconcileTrigger t = ReconcileTrigger.launch, String? error}) => ReconcileRun(
    at: base.add(Duration(minutes: minute)),
    trigger: t,
    planned: minute,
    added: 1,
    cancelled: 2,
    error: error,
  );

  test('record round-trips every field, newest first', () async {
    await repo.record(run(1));
    await repo.record(run(3, t: ReconcileTrigger.timezoneChange, error: 'boom'));
    await repo.record(run(2));
    final runs = await repo.watchRecent().first;
    expect(runs.map((r) => r.planned), [3, 2, 1]);
    expect(runs.first, run(3, t: ReconcileTrigger.timezoneChange, error: 'boom'));
  });

  test('watchRecent honours limit and re-emits on write', () async {
    for (var i = 0; i < 5; i++) {
      await repo.record(run(i));
    }
    expect((await repo.watchRecent(limit: 2).first).map((r) => r.planned), [4, 3]);

    final next = repo.watchRecent(limit: 2).skip(1).first;
    await repo.record(run(10));
    expect((await next).map((r) => r.planned), [10, 4]);
  });

  test('prune keeps only the newest N', () async {
    for (var i = 0; i < 10; i++) {
      await repo.record(run(i));
    }
    await repo.prune(keep: 3);
    expect((await repo.watchRecent().first).map((r) => r.planned), [9, 8, 7]);
    await repo.prune();
    expect(await repo.watchRecent().first, hasLength(3));
  });
}
