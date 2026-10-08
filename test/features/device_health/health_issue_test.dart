import 'package:flutter_test/flutter_test.dart';
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
