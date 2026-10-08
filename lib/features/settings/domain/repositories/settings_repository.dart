import 'package:knight_rise/features/settings/domain/entities/app_settings.dart';

abstract interface class SettingsRepository {
  Stream<AppSettings> watch();

  Future<AppSettings> get();

  Future<void> save(AppSettings settings);

  /// Writes only `lastRetentionRunAt`, so a background run cannot overwrite
  /// a settings change made meanwhile (as a read-modify-[save] could).
  Future<void> markRetentionRun(DateTime at);
}
