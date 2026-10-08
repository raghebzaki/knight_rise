import 'package:knight_rise/features/device_health/domain/device_health_report.dart';

abstract interface class DeviceHealthRepository {
  /// Reads the current state of every health signal. Never throws; unknown
  /// signals come back null.
  Future<DeviceHealthReport> load();
}
