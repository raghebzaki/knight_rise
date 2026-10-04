import 'package:knight_rise/features/settings/domain/entities/app_settings.dart';

abstract interface class SettingsRepository {
  Stream<AppSettings> watch();

  Future<AppSettings> get();

  Future<void> save(AppSettings settings);
}
