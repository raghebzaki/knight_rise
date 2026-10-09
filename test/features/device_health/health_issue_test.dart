import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';
import 'package:knight_rise/features/device_health/domain/device_health_report.dart';
import 'package:knight_rise/features/device_health/domain/health_issue.dart';
import 'package:knight_rise/features/device_health/domain/oem_guide.dart';

DeviceHealthReport report({
  bool notifications = true,
  bool precision = false,
  bool exact = true,
  bool? battery = true,
  BackgroundRefresh? refresh,
  String maker = 'Google Pixel',
  HealthPlatform platform = HealthPlatform.android,
}) => DeviceHealthReport(
  notificationsEnabled: notifications,
  precisionTiming: precision,
  exactAlarmsAllowed: exact,
  batteryOptimizationIgnored: battery,
  backgroundRefresh: refresh,
  manufacturer: maker,
  platform: platform,
);

void main() {
  desktopIssueTests();
  group('issuesOf', () {
    test('a healthy device has no issues', () {
      expect(issuesOf(report()), isEmpty);
    });

    test('notifications off is an error', () {
      expect(issuesOf(report(notifications: false)), [
        const HealthIssue(HealthKind.notifications, HealthSeverity.error),
      ]);
    });

    test('exact alarms only matter when Precision Timing is on', () {
      expect(issuesOf(report(exact: false)), isEmpty);
      expect(issuesOf(report(precision: true, exact: false)), [
        const HealthIssue(HealthKind.exactAlarms, HealthSeverity.warning),
      ]);
      expect(issuesOf(report(precision: true)), isEmpty);
    });

    test('battery optimization is a warning on aggressive OEMs, info elsewhere', () {
      for (final maker in [
        'Xiaomi',
        'Redmi',
        'POCO',
        'HUAWEI',
        'honor',
        'OPPO',
        'realme',
        'OnePlus',
        'vivo',
        'iQOO',
        'samsung',
        'Meizu',
        'ASUS',
        'Xiaomi Redmi',
      ]) {
        expect(issuesOf(report(battery: false, maker: maker)), [
          const HealthIssue(HealthKind.battery, HealthSeverity.warning),
        ], reason: maker);
      }
      for (final maker in ['Google Pixel', 'motorola', '']) {
        expect(issuesOf(report(battery: false, maker: maker)), [
          const HealthIssue(HealthKind.battery, HealthSeverity.info),
        ], reason: maker);
      }
    });

    test('unknown battery state and ignored optimization raise nothing', () {
      expect(issuesOf(report(battery: null, maker: 'Xiaomi')), isEmpty);
      expect(issuesOf(report(maker: 'Xiaomi')), isEmpty);
    });

    test('iOS background refresh denied or restricted is a warning; battery is Android-only', () {
      const ios = HealthPlatform.ios;
      expect(issuesOf(report(platform: ios, battery: null, refresh: BackgroundRefresh.available)), isEmpty);
      for (final r in [BackgroundRefresh.denied, BackgroundRefresh.restricted]) {
        expect(issuesOf(report(platform: ios, battery: null, refresh: r)), [
          const HealthIssue(HealthKind.backgroundRefresh, HealthSeverity.warning),
        ]);
      }
      expect(issuesOf(report(platform: ios, battery: false, maker: 'Xiaomi')), isEmpty);
    });

    test('issues are ordered by importance and actionableIssues drops info', () {
      final issues = issuesOf(report(notifications: false, precision: true, exact: false, battery: false));
      expect(issues.map((i) => i.kind), [HealthKind.notifications, HealthKind.exactAlarms, HealthKind.battery]);
      expect(actionableIssues(issues).map((i) => i.kind), [HealthKind.notifications, HealthKind.exactAlarms]);
    });
  });

  group('guideFor', () {
    test('maps makers case-insensitively', () {
      expect(guideFor('Xiaomi').maker, OemMaker.xiaomi);
      expect(guideFor('REDMI').maker, OemMaker.xiaomi);
      expect(guideFor('poco').maker, OemMaker.xiaomi);
      expect(guideFor('samsung').maker, OemMaker.samsung);
      expect(guideFor('HUAWEI').maker, OemMaker.huawei);
      expect(guideFor('Honor').maker, OemMaker.huawei);
      expect(guideFor('OPPO').maker, OemMaker.oppo);
      expect(guideFor('realme').maker, OemMaker.oppo);
      expect(guideFor('OnePlus').maker, OemMaker.oppo);
      expect(guideFor('vivo').maker, OemMaker.vivo);
      expect(guideFor('iQOO').maker, OemMaker.vivo);
      expect(guideFor('Google Pixel').maker, OemMaker.generic);
      expect(guideFor('').maker, OemMaker.generic);
    });

    test('known makers carry settings components, the fallback has none', () {
      expect(guideFor('xiaomi').settingsComponents.single, contains('com.miui.securitycenter/'));
      expect(guideFor('huawei').settingsComponents.single, contains('com.huawei.systemmanager/'));
      expect(guideFor('oppo').settingsComponents.single, contains('com.coloros.safecenter/'));
      expect(guideFor('vivo').settingsComponents.single, contains('com.vivo.permissionmanager/'));
      expect(guideFor('samsung').settingsComponents.single, contains('com.samsung.android.lool/'));
      expect(guideFor('pixel').settingsComponents, isEmpty);
    });
  });
}

/// Desktop reports. [beatAge] is how old the last heartbeat is at check time.
DeviceHealthReport desktopReport({
  HealthPlatform platform = HealthPlatform.macos,
  bool notifications = true,
  bool verifiable = true,
  LaunchAtLoginStatus? login = LaunchAtLoginStatus.enabled,
  Duration? beatAge = const Duration(seconds: 30),
  Duration? lag,
  bool? appNap = true,
}) {
  final now = DateTime(2026, 1, 1, 12);
  return DeviceHealthReport(
    platform: platform,
    notificationsEnabled: notifications,
    notificationsVerifiable: verifiable,
    precisionTiming: false,
    exactAlarmsAllowed: true,
    launchAtLogin: login,
    lastHeartbeatAt: beatAge == null ? null : now.subtract(beatAge),
    timerLag: lag,
    checkedAt: now,
    appNapDisabled: appNap,
  );
}

void desktopIssueTests() {
  group('issuesOf (desktop)', () {
    test('a healthy Mac has no issues', () {
      expect(issuesOf(desktopReport()), isEmpty);
    });

    test('a healthy Windows PC only carries the unverified-notifications hint', () {
      expect(issuesOf(desktopReport(platform: HealthPlatform.windows, verifiable: false, appNap: null)), [
        const HealthIssue(HealthKind.notificationsUnverified, HealthSeverity.info),
      ]);
      expect(
        actionableIssues(issuesOf(desktopReport(platform: HealthPlatform.windows, verifiable: false, appNap: null))),
        isEmpty,
      );
    });

    test('macOS notifications off is an error', () {
      expect(issuesOf(desktopReport(notifications: false)), [
        const HealthIssue(HealthKind.notifications, HealthSeverity.error),
      ]);
    });

    test('Windows never reports blocked notifications (cannot be read)', () {
      expect(
        issuesOf(desktopReport(platform: HealthPlatform.windows, notifications: false, verifiable: false))
            .map((i) => i.kind),
        [HealthKind.notificationsUnverified],
      );
    });

    test('launch at login: managed by the system raises nothing', () {
      for (final platform in [HealthPlatform.macos, HealthPlatform.windows]) {
        expect(
          issuesOf(desktopReport(platform: platform, login: LaunchAtLoginStatus.managedBySystem))
              .where((i) => i.kind == HealthKind.launchAtLogin),
          isEmpty,
        );
      }
    });

    test('launch at login: disabled / needs approval warn, unavailable informs, enabled and unknown are fine', () {
      for (final platform in [HealthPlatform.macos, HealthPlatform.windows]) {
        for (final s in [LaunchAtLoginStatus.disabled, LaunchAtLoginStatus.requiresApproval]) {
          expect(
            issuesOf(desktopReport(platform: platform, login: s)).where((i) => i.kind == HealthKind.launchAtLogin),
            [const HealthIssue(HealthKind.launchAtLogin, HealthSeverity.warning)],
            reason: '$platform $s',
          );
        }
        expect(
          issuesOf(desktopReport(platform: platform, login: LaunchAtLoginStatus.unavailable))
              .where((i) => i.kind == HealthKind.launchAtLogin),
          [const HealthIssue(HealthKind.launchAtLogin, HealthSeverity.info)],
        );
        expect(
          issuesOf(desktopReport(platform: platform, login: null)).where((i) => i.kind == HealthKind.launchAtLogin),
          isEmpty,
        );
      }
    });

    test('heartbeat: timers firing over 30 s late (sleep excluded) are throttled', () {
      expect(issuesOf(desktopReport(lag: const Duration(seconds: 30))), isEmpty);
      expect(issuesOf(desktopReport(lag: const Duration(seconds: 31))), [
        const HealthIssue(HealthKind.heartbeat, HealthSeverity.error),
      ]);
      expect(
        issuesOf(desktopReport(platform: HealthPlatform.android, lag: const Duration(minutes: 5))),
        isNot(contains(const HealthIssue(HealthKind.heartbeat, HealthSeverity.error))),
      );
    });

    test('heartbeat: error only when older than 3 minutes; none before the first beat', () {
      expect(issuesOf(desktopReport(beatAge: const Duration(minutes: 3))), isEmpty);
      expect(issuesOf(desktopReport(beatAge: const Duration(minutes: 3, seconds: 1))), [
        const HealthIssue(HealthKind.heartbeat, HealthSeverity.error),
      ]);
      expect(issuesOf(desktopReport(beatAge: null)), isEmpty);
    });

    test('App Nap warns on macOS only when known to be on', () {
      expect(issuesOf(desktopReport(appNap: false)), [const HealthIssue(HealthKind.appNap, HealthSeverity.warning)]);
      expect(issuesOf(desktopReport(appNap: null)), isEmpty);
      expect(issuesOf(desktopReport(platform: HealthPlatform.windows, appNap: false)), isEmpty);
    });

    test('combined problems keep a stable order', () {
      expect(
        issuesOf(
          desktopReport(
            notifications: false,
            beatAge: const Duration(minutes: 10),
            login: LaunchAtLoginStatus.disabled,
            appNap: false,
          ),
        ).map((i) => i.kind),
        [HealthKind.notifications, HealthKind.heartbeat, HealthKind.launchAtLogin, HealthKind.appNap],
      );
    });

    test('mobile ignores desktop-only fields', () {
      final r = DeviceHealthReport(
        platform: HealthPlatform.android,
        notificationsEnabled: true,
        precisionTiming: false,
        exactAlarmsAllowed: true,
        launchAtLogin: LaunchAtLoginStatus.disabled,
        appNapDisabled: false,
        lastHeartbeatAt: DateTime(2020),
        checkedAt: DateTime(2026),
      );
      expect(issuesOf(r), isEmpty);
    });
  });
}
