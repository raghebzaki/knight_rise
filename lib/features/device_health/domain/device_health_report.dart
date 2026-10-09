import 'package:equatable/equatable.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';

/// iOS Background App Refresh state for this app.
enum BackgroundRefresh { available, denied, restricted }

enum HealthPlatform { android, ios, macos, windows, other }

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
    this.launchAtLogin,
    this.lastHeartbeatAt,
    this.timerLag,
    this.checkedAt,
    this.appNapDisabled,
    this.notificationsVerifiable = true,
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

  /// Desktop: whether the app starts at sign-in; null when unknown or mobile.
  final LaunchAtLoginStatus? launchAtLogin;

  /// Desktop: when the reminder heartbeat last completed a beat; null before
  /// the first beat or on mobile.
  final DateTime? lastHeartbeatAt;

  /// Desktop: how late the last timer beat fired on the monotonic clock
  /// (throttling, not sleep); null when not measured yet.
  final Duration? timerLag;

  /// When this report was gathered (desktop). The heartbeat age is measured
  /// against it so the issue rules stay pure.
  final DateTime? checkedAt;

  /// macOS: true while the runner holds the activity that opts out of App Nap;
  /// null when unknown or not macOS.
  final bool? appNapDisabled;

  /// False when the OS toggle cannot be read (Windows): [notificationsEnabled]
  /// is then an assumption, not a fact.
  final bool notificationsVerifiable;

  @override
  List<Object?> get props => [
    notificationsEnabled,
    precisionTiming,
    exactAlarmsAllowed,
    batteryOptimizationIgnored,
    backgroundRefresh,
    manufacturer,
    platform,
    launchAtLogin,
    lastHeartbeatAt,
    timerLag,
    checkedAt,
    appNapDisabled,
    notificationsVerifiable,
  ];
}
