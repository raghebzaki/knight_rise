import 'package:knight_rise/features/quest_log/domain/entities/daily_summary.dart';

abstract interface class DailySummaryRepository {
  /// Summaries dated [date] or later, oldest first. Emits again on every
  /// write, including writes from a background isolate.
  Stream<List<DailySummary>> watchFrom(DateTime date);

  Future<List<DailySummary>> getFrom(DateTime date);

  /// Date of the most recent stored summary, or null when there is none.
  Future<DateTime?> latestDate();

  /// Inserts or replaces the summary of `summary.date`, routines included,
  /// in one transaction.
  Future<void> upsert(DailySummary summary);
}
