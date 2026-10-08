import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/quest_log/domain/entities/knight_rank.dart';
import 'package:knight_rise/features/quest_log/domain/services/quest_measure.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';

void main() {
  group('QuestMeasure', () {
    QuestMeasure of(RoutineType t, {int done = 3, int target = 8, int waterMl = 1250, int waterTargetMl = 2000}) =>
        QuestMeasure.of(t, done: done, target: target, waterMl: waterMl, waterTargetMl: waterTargetMl);

    test('hydration is measured in ml, other routines in completions', () {
      expect(of(RoutineType.hydration), const QuestMeasure(1250, 2000));
      expect(of(RoutineType.stretch), const QuestMeasure(3, 8));
      expect(of(RoutineType.eyeRest), const QuestMeasure(3, 8));
    });

    test('a 500 ml glass counts twice as much as 250 ml', () {
      expect(of(RoutineType.hydration, done: 1, waterMl: 500).fraction, 0.25);
      expect(of(RoutineType.hydration, done: 1, waterMl: 250).fraction, 0.125);
    });

    test('fraction is clamped to 0..1', () {
      expect(const QuestMeasure(0, 6).fraction, 0);
      expect(const QuestMeasure(9, 6).fraction, 1);
      expect(const QuestMeasure(3, 6).fraction, 0.5);
    });

    test('reaches uses exact integer math at the threshold', () {
      // 70 % of 8 = 5.6 → 6 needed.
      expect(const QuestMeasure(6, 8).reaches(70), isTrue);
      expect(const QuestMeasure(5, 8).reaches(70), isFalse);
      // 70 % of 2000 ml = 1400 ml exactly.
      expect(const QuestMeasure(1400, 2000).reaches(70), isTrue);
      expect(const QuestMeasure(1399, 2000).reaches(70), isFalse);
      // 70 % of 10 = 7 exactly (no float near-miss).
      expect(const QuestMeasure(7, 10).reaches(70), isTrue);
      expect(const QuestMeasure(12, 12).reaches(100), isTrue);
      expect(const QuestMeasure(0, 12).reaches(0), isTrue);
    });

    test('a non-positive goal counts as reached', () {
      expect(const QuestMeasure(0, 0).fraction, 1);
      expect(const QuestMeasure(0, 0).reaches(70), isTrue);
    });
  });

  group('KnightRank', () {
    test('forStreak: Page 0–2, Squire 3–6, Knight 7–29, Paladin 30+', () {
      expect([
        for (final d in [0, 1, 2]) KnightRank.forStreak(d),
      ], everyElement(KnightRank.page));
      expect([
        for (final d in [3, 6]) KnightRank.forStreak(d),
      ], everyElement(KnightRank.squire));
      expect([
        for (final d in [7, 29]) KnightRank.forStreak(d),
      ], everyElement(KnightRank.knight));
      expect([
        for (final d in [30, 365]) KnightRank.forStreak(d),
      ], everyElement(KnightRank.paladin));
    });

    test('next and daysToNext', () {
      expect(KnightRank.page.next, KnightRank.squire);
      expect(KnightRank.page.daysToNext(1), 2);
      expect(KnightRank.squire.daysToNext(3), 4);
      expect(KnightRank.knight.daysToNext(12), 18);
      expect(KnightRank.paladin.next, isNull);
      expect(KnightRank.paladin.daysToNext(40), isNull);
    });
  });
}
