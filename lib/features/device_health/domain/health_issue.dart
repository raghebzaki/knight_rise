import 'package:equatable/equatable.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';
import 'package:knight_rise/features/device_health/domain/device_health_report.dart';
import 'package:knight_rise/features/device_health/domain/oem_guide.dart';

enum HealthKind {
  notifications,
  exactAlarms,
  battery,
  backgroundRefresh,

  /// Desktop: the app will not start at sign-in.
  launchAtLogin,

  /// Desktop: the reminder heartbeat stopped, or its timers are throttled.
  heartbeat,

  /// macOS: App Nap may throttle the app's timers.
  appNap,

  /// Windows: the notification toggle cannot be read by the app.
  notificationsUnverified,
}

enum HealthSeverity { error, warning, info }

class HealthIssue extends Equatable {
  const HealthIssue(this.kind, this.severity);

  final HealthKind kind;
  final HealthSeverity severity;

  @override
  List<Object?> get props => [kind, severity];
}

/// A heartbeat older than this, even after an on-demand beat, means it stopped.
const Duration heartbeatStaleAfter = Duration(minutes: 3);

/// A timer beat firing later than this (monotonic, sleep excluded) means the
/// OS is throttling the app's timers, e.g. App Nap.
const Duration heartbeatMaxLag = Duration(seconds: 30);

/// The problems found in [report], most important first.
List<HealthIssue> issuesOf(DeviceHealthReport report) {
  final android = report.platform == HealthPlatform.android;
  final ios = report.platform == HealthPlatform.ios;
  final macos = report.platform == HealthPlatform.macos;
  final desktop = macos || report.platform == HealthPlatform.windows;
  final beat = report.lastHeartbeatAt;
  final checked = report.checkedAt;
  final login = report.launchAtLogin;
  return [
    if (report.notificationsVerifiable && !report.notificationsEnabled)
      const HealthIssue(HealthKind.notifications, HealthSeverity.error),
    if (desktop && !report.notificationsVerifiable)
      const HealthIssue(HealthKind.notificationsUnverified, HealthSeverity.info),
    if (desktop &&
        ((beat != null && checked != null && checked.difference(beat) > heartbeatStaleAfter) ||
            (report.timerLag ?? Duration.zero) > heartbeatMaxLag))
      const HealthIssue(HealthKind.heartbeat, HealthSeverity.error),
    if (report.precisionTiming && !report.exactAlarmsAllowed)
      const HealthIssue(HealthKind.exactAlarms, HealthSeverity.warning),
    if (android && report.batteryOptimizationIgnored == false)
      HealthIssue(
        HealthKind.battery,
        isAggressiveOem(report.manufacturer) ? HealthSeverity.warning : HealthSeverity.info,
      ),
    if (ios &&
        (report.backgroundRefresh == BackgroundRefresh.denied ||
            report.backgroundRefresh == BackgroundRefresh.restricted))
      const HealthIssue(HealthKind.backgroundRefresh, HealthSeverity.warning),
    if (desktop && (login == LaunchAtLoginStatus.disabled || login == LaunchAtLoginStatus.requiresApproval))
      const HealthIssue(HealthKind.launchAtLogin, HealthSeverity.warning),
    if (desktop && login == LaunchAtLoginStatus.unavailable)
      const HealthIssue(HealthKind.launchAtLogin, HealthSeverity.info),
    if (macos && report.appNapDisabled == false) const HealthIssue(HealthKind.appNap, HealthSeverity.warning),
  ];
}

/// Issues worth interrupting the user for (warning or error).
List<HealthIssue> actionableIssues(Iterable<HealthIssue> issues) => [
  for (final i in issues)
    if (i.severity != HealthSeverity.info) i,
];
