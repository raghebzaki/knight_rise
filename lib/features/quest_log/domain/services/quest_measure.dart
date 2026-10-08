import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:meta/meta.dart';

/// What counts toward a routine's daily goal: ml logged against the ml
/// target for hydration, completions against the daily target otherwise.
/// One rule for the live dashboard, finalized summaries and streaks.
@immutable
class QuestMeasure {
  const QuestMeasure(this.value, this.goal);

  factory QuestMeasure.of(
    RoutineType type, {
    required int done,
    required int target,
    required int waterMl,
    required int waterTargetMl,
  }) => type == RoutineType.hydration ? QuestMeasure(waterMl, waterTargetMl) : QuestMeasure(done, target);

  final int value;
  final int goal;

  /// Share of the goal reached, clamped to 0..1. A goal of zero or less
  /// counts as reached.
  double get fraction => goal <= 0 ? 1 : (value / goal).clamp(0, 1).toDouble();

  /// True when at least [percent] % of the goal is reached. Integer math, so
  /// 70 % of 8 needs 6 (5.6 rounded up), never a float near-miss.
  bool reaches(int percent) => goal <= 0 || value * 100 >= percent * goal;

  @override
  bool operator ==(Object other) => other is QuestMeasure && other.value == value && other.goal == goal;

  @override
  int get hashCode => Object.hash(value, goal);

  @override
  String toString() => 'QuestMeasure($value / $goal)';
}
