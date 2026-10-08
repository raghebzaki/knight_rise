import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/features/device_health/domain/device_health_report.dart';

/// Native device-health queries (MethodChannel `knight_rise/device_health`).
/// Every method returns null / false instead of throwing, e.g. when the
/// native side is missing (tests, desktop).
abstract interface class DeviceHealthPlatform {
  /// Android: whether the app is exempt from battery optimization.
  Future<bool?> isIgnoringBatteryOptimizations();

  /// iOS: Background App Refresh state.
  Future<BackgroundRefresh?> backgroundRefreshStatus();

  /// iOS: opens this app's page in the Settings app. Returns success.
  Future<bool> openAppSettings();
}

const String kDeviceHealthChannel = 'knight_rise/device_health';

@LazySingleton(as: DeviceHealthPlatform)
class MethodChannelDeviceHealthPlatform implements DeviceHealthPlatform {
  MethodChannelDeviceHealthPlatform();

  static const MethodChannel _channel = MethodChannel(kDeviceHealthChannel);

  @override
  Future<bool?> isIgnoringBatteryOptimizations() => _call<bool>('isIgnoringBatteryOptimizations');

  @override
  Future<BackgroundRefresh?> backgroundRefreshStatus() async =>
      switch (await _call<String>('backgroundRefreshStatus')) {
        'available' => BackgroundRefresh.available,
        'denied' => BackgroundRefresh.denied,
        'restricted' => BackgroundRefresh.restricted,
        _ => null,
      };

  @override
  Future<bool> openAppSettings() async => await _call<bool>('openAppSettings') ?? false;

  Future<T?> _call<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
