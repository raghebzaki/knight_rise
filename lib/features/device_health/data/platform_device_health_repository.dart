import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/features/device_health/data/device_health_platform.dart';
import 'package:knight_rise/features/device_health/data/device_identity.dart';
import 'package:knight_rise/features/device_health/domain/device_health_report.dart';
import 'package:knight_rise/features/device_health/domain/device_health_repository.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';

/// Android / iOS health signals.
@mobileEnv
@LazySingleton(as: DeviceHealthRepository)
class PlatformDeviceHealthRepository implements DeviceHealthRepository {
  PlatformDeviceHealthRepository(this._gateway, this._platform, this._identity, this._settings);

  final NotificationGateway _gateway;
  final DeviceHealthPlatform _platform;
  final DeviceIdentity _identity;
  final SettingsRepository _settings;

  @override
  Future<DeviceHealthReport> load() async {
    final target = switch (defaultTargetPlatform) {
      TargetPlatform.android => HealthPlatform.android,
      TargetPlatform.iOS => HealthPlatform.ios,
      _ => HealthPlatform.other,
    };
    final settings = await _settings.get();
    return DeviceHealthReport(
      platform: target,
      notificationsEnabled: await _gateway.notificationsEnabled(),
      precisionTiming: settings.precisionTiming,
      exactAlarmsAllowed: await _gateway.canScheduleExact(),
      batteryOptimizationIgnored: target == HealthPlatform.android
          ? await _platform.isIgnoringBatteryOptimizations()
          : null,
      backgroundRefresh: target == HealthPlatform.ios ? await _platform.backgroundRefreshStatus() : null,
      manufacturer: await _identity.manufacturer(),
    );
  }
}
