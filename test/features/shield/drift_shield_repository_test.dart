import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/features/shield/data/drift_shield_repository.dart';
import 'package:knight_rise/features/shield/domain/entities/shield_session.dart';

DateTime t(int h, [int m = 0, int day = 5]) => DateTime.utc(2026, 10, day, h, m);

void main() {
  late AppDatabase db;
  late DriftShieldRepository repo;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftShieldRepository(db);
  });
  tearDown(() => db.close());

  ShieldSession session(int sh, int eh, {DateTime? endedAt, ShieldReason reason = ShieldReason.focus, int day = 5}) =>
      ShieldSession(startAt: t(sh, 0, day), endAt: t(eh, 0, day), endedAt: endedAt, reason: reason);

  bool same(DateTime a, DateTime b) => a.isAtSameMomentAs(b);

  test('add / getSince round-trips every field and assigns ids', () async {
    final id1 = await repo.add(session(10, 11, endedAt: t(10, 30), reason: ShieldReason.meeting));
    final id2 = await repo.add(session(12, 13, reason: ShieldReason.untilOff));
    expect([id1, id2], [1, 2]);

    final all = await repo.getSince(t(0));
    expect(all.map((s) => s.id), [1, 2]);
    expect(all.map((s) => s.reason), [ShieldReason.meeting, ShieldReason.untilOff]);
    expect(same(all[0].startAt, t(10)), isTrue);
    expect(same(all[0].endAt, t(11)), isTrue);
    expect(same(all[0].endedAt!, t(10, 30)), isTrue);
    expect(all[1].endedAt, isNull);
  });

  test('update replaces the stored values', () async {
    final id = await repo.add(session(10, 11));
    await repo.update(session(10, 12, endedAt: t(10, 40), reason: ShieldReason.custom).copyWith(id: id));
    final s = (await repo.getSince(t(0))).single;
    expect(same(s.endAt, t(12)), isTrue);
    expect(same(s.endedAt!, t(10, 40)), isTrue);
    expect(s.reason, ShieldReason.custom);
    expect(() => repo.update(session(10, 11)), throwsArgumentError);
  });

  test('watchSince / getSince filter on the effective end (endedAt wins when earlier)', () async {
    await repo.add(session(8, 9)); // ended 09:00
    await repo.add(session(9, 12, endedAt: t(9, 30))); // planned 12:00 but ended 09:30
    await repo.add(session(13, 14));
    await repo.add(session(1, 2, day: 4)); // yesterday

    List<int?> ids(List<ShieldSession> l) => l.map((s) => s.id).toList();
    expect(ids(await repo.getSince(t(0))), [1, 2, 3]);
    expect(ids(await repo.getSince(t(9, 15))), [2, 3]);
    expect(ids(await repo.getSince(t(9, 30))), [3]); // 09:30 effective end is not "after" 09:30
    expect(ids(await repo.getSince(t(14))), isEmpty);
    expect(ids(await repo.watchSince(t(9, 15)).first), [2, 3]);
  });

  test('watchSince emits again after a write', () async {
    final emissions = <List<int?>>[];
    final sub = repo.watchSince(t(0)).listen((l) => emissions.add(l.map((s) => s.id).toList()));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await repo.add(session(10, 11));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(emissions, [
      <int?>[],
      [1],
    ]);
  });

  test('active picks the session covering now, honoring endedAt', () async {
    expect(await repo.active(t(10)), isNull);
    await repo.add(session(10, 12));
    await repo.add(session(9, 11, endedAt: t(9, 30)));
    expect((await repo.active(t(10, 30)))!.id, 1);
    expect((await repo.active(t(10)))!.id, 1);
    expect(await repo.active(t(9, 59)), isNull); // second one ended 09:30, first not started
    expect((await repo.active(t(9, 10)))!.id, 2);
    expect(await repo.active(t(12)), isNull); // end is exclusive
  });

  test('active returns the latest started when sessions overlap', () async {
    await repo.add(session(10, 13));
    await repo.add(session(11, 12));
    expect((await repo.active(t(11, 30)))!.id, 2);
  });
}
