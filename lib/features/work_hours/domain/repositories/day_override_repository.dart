import 'package:knight_rise/features/work_hours/domain/entities/day_override.dart';

abstract interface class DayOverrideRepository {
  /// Overrides dated [date] or later, ordered by date.
  Stream<List<DayOverride>> watchFrom(DateTime date);

  Future<List<DayOverride>> getFrom(DateTime date);

  /// Inserts or replaces the override of `override.date`.
  Future<void> set(DayOverride override);

  /// Removes the override of [date], if any.
  Future<void> clear(DateTime date);
}
