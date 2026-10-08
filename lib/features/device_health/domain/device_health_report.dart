import 'package:equatable/equatable.dart';

/// iOS Background App Refresh state for this app.
enum BackgroundRefresh { available, denied, restricted }

enum HealthPlatform { android, ios, other }

/// Everything the Device health screen needs, gathered once per refresh.
class DeviceHealthReport extends Equatable {
  const DeviceHealthReport({
    required this.notificationsEnabled,
    required this.precisionTiming,
    required this.exactAlarmsAllowed,
    required this.platform,
    this.batteryOptimizationIgnored,
    this.backgroundRefresh,
    this.manufacturer = '',
  });

  final bool notificationsEnabled;

  /// The user's "Precision Timing" setting (wants exact alarms).
  final bool precisionTiming;

  /// Whether the OS currently lets the app schedule exact alarms.
  final bool exactAlarmsAllowed;

  /// Android: true when the app is exempt from battery optimization; null when unknown.
  final bool? batteryOptimizationIgnored;

  /// iOS only; null when unknown or on Android.
  final BackgroundRefresh? backgroundRefresh;

  /// Device manufacturer and brand, e.g. `Xiaomi Redmi`. Empty when unknown.
  final String manufacturer;
  final HealthPlatform platform;

  @override
  List<Object?> get props => [
    notificationsEnabled,
    precisionTiming,
    exactAlarmsAllowed,
    batteryOptimizationIgnored,
    backgroundRefresh,
    manufacturer,
    platform,
  ];
}
