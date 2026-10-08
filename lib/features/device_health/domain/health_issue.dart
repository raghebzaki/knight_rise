import 'package:equatable/equatable.dart';
import 'package:knight_rise/features/device_health/domain/device_health_report.dart';
import 'package:knight_rise/features/device_health/domain/oem_guide.dart';

enum HealthKind { notifications, exactAlarms, battery, backgroundRefresh }

enum HealthSeverity { error, warning, info }

class HealthIssue extends Equatable {
  const HealthIssue(this.kind, this.severity);

  final HealthKind kind;
  final HealthSeverity severity;

  @override
  List<Object?> get props => [kind, severity];
}

/// The problems found in [report], most important first.
List<HealthIssue> issuesOf(DeviceHealthReport report) {
  final android = report.platform == HealthPlatform.android;
  final ios = report.platform == HealthPlatform.ios;
  return [
    if (!report.notificationsEnabled) const HealthIssue(HealthKind.notifications, HealthSeverity.error),
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
  ];
}

/// Issues worth interrupting the user for (warning or error).
List<HealthIssue> actionableIssues(Iterable<HealthIssue> issues) => [
  for (final i in issues)
    if (i.severity != HealthSeverity.info) i,
];
