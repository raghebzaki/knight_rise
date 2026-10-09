import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';
import 'package:knight_rise/features/device_health/domain/device_health_report.dart';
import 'package:knight_rise/features/device_health/domain/health_issue.dart';
import 'package:knight_rise/features/device_health/domain/oem_guide.dart';

import '../../helpers/health_fakes.dart';

void main() {
  late HealthHarness h;

  setUp(() => h = HealthHarness());
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    return h.cubit.close();
  });

  group('refresh', () {
    test('loads the report and its issues', () async {
      h.gateway.enabled = false;
      expect(h.cubit.state.loaded, isFalse);
      await h.cubit.refresh();
      expect(h.cubit.state.loaded, isTrue);
      expect(h.cubit.state.issues, [const HealthIssue(HealthKind.notifications, HealthSeverity.error)]);
      h.gateway.enabled = true;
      await h.cubit.refresh();
      expect(h.cubit.state.issues, isEmpty);
    });
  });

  group('notifications fix', () {
    test('granting the prompt needs no settings screen', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      h.gateway.enabled = false;
      await h.cubit.fix(HealthKind.notifications);
      expect(h.gateway.requestPermissionCalls, 1);
      expect(h.launcher.calls, isEmpty);
      expect(h.cubit.state.issues, isEmpty);
    });

    test('Android: when the prompt does not enable them, opens app notification settings', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      h.gateway
        ..enabled = false
        ..grantOnRequest = false;
      await h.cubit.fix(HealthKind.notifications);
      expect(h.launcher.calls, ['notifications']);
    });

    test('Android: falls back to app details when the intent fails', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      h.gateway
        ..enabled = false
        ..grantOnRequest = false;
      h.launcher.intentsSucceed = false;
      await h.cubit.fix(HealthKind.notifications);
      expect(h.launcher.calls, ['notifications', 'details']);
    });

    test('iOS: opens app settings through the platform channel', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      h.gateway
        ..enabled = false
        ..grantOnRequest = false;
      await h.cubit.fix(HealthKind.notifications);
      expect(h.platformFake.openAppSettingsCalls, 1);
      expect(h.launcher.calls, isEmpty);
    });
  });

  group('Precision Timing', () {
    test('ON while exact alarms are allowed saves immediately', () async {
      await h.cubit.setPrecisionTiming(value: true);
      expect(h.settings.current.precisionTiming, isTrue);
      expect(h.gateway.requestExactAlarmPermissionCalls, 0);
    });

    test('ON while not allowed requests the permission, then saves once a refresh sees it allowed', () async {
      h.gateway.exactAllowed = false;
      await h.cubit.setPrecisionTiming(value: true);
      expect(h.gateway.requestExactAlarmPermissionCalls, 1);
      expect(h.settings.current.precisionTiming, isFalse);
      expect(h.cubit.state.awaitingExactAlarms, isTrue);

      await h.cubit.refresh(); // still denied
      expect(h.settings.current.precisionTiming, isFalse);
      expect(h.cubit.state.awaitingExactAlarms, isTrue);

      h.gateway.exactAllowed = true; // user flipped it in system settings and came back
      await h.cubit.refresh();
      expect(h.settings.current.precisionTiming, isTrue);
      expect(h.cubit.state.awaitingExactAlarms, isFalse);
      expect(h.cubit.state.report!.precisionTiming, isTrue);
    });

    test('OFF saves false and cancels a pending request', () async {
      await h.settings.save(h.settings.current.copyWith(precisionTiming: true));
      await h.cubit.setPrecisionTiming(value: false);
      expect(h.settings.current.precisionTiming, isFalse);

      h.gateway.exactAllowed = false;
      await h.cubit.setPrecisionTiming(value: true);
      await h.cubit.setPrecisionTiming(value: false);
      h.gateway.exactAllowed = true;
      await h.cubit.refresh();
      expect(h.settings.current.precisionTiming, isFalse);
    });

    test('fix(exactAlarms) re-requests the permission without changing the setting', () async {
      await h.settings.save(h.settings.current.copyWith(precisionTiming: true));
      h.gateway.exactAllowed = false;
      await h.cubit.refresh();
      expect(h.cubit.state.issue(HealthKind.exactAlarms), isNotNull);
      await h.cubit.fix(HealthKind.exactAlarms);
      expect(h.gateway.requestExactAlarmPermissionCalls, 1);
      expect(h.settings.current.precisionTiming, isTrue);
    });
  });

  group('battery and background refresh fixes', () {
    test('battery opens the optimization list', () async {
      await h.cubit.fix(HealthKind.battery);
      expect(h.launcher.calls, ['battery']);
    });

    test('battery falls back to app details', () async {
      h.launcher.intentsSucceed = false;
      await h.cubit.fix(HealthKind.battery);
      expect(h.launcher.calls, ['battery', 'details']);
    });

    test('background refresh opens iOS settings', () async {
      await h.cubit.fix(HealthKind.backgroundRefresh);
      expect(h.platformFake.openAppSettingsCalls, 1);
    });
  });

  group('openOemSettings', () {
    test('tries components in order and stops at the first that opens', () async {
      h.launcher.availableComponents = {'b/B'};
      await h.cubit.openOemSettings(const OemGuide(OemMaker.xiaomi, settingsComponents: ['a/A', 'b/B', 'c/C']));
      expect(h.launcher.calls, ['component:a/A', 'component:b/B']);
    });

    test('falls back to app details on Android when none open', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await h.cubit.openOemSettings(guideFor('xiaomi'));
      expect(h.launcher.calls.last, 'details');
      h.launcher.calls.clear();
      await h.cubit.openOemSettings(guideFor('pixel'));
      expect(h.launcher.calls, ['details']);
    });
  });

  test('report platform is carried through', () async {
    final ios = HealthHarness(platform: HealthPlatform.ios);
    addTearDown(ios.cubit.close);
    ios.platformFake.refresh = BackgroundRefresh.denied;
    await ios.cubit.refresh();
    expect(ios.cubit.state.issues, [const HealthIssue(HealthKind.backgroundRefresh, HealthSeverity.warning)]);
  });

  group('desktop fixes', () {
    test('macOS: a refused notification prompt opens the notification settings', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      h.gateway
        ..enabled = false
        ..grantOnRequest = false;
      await h.cubit.fix(HealthKind.notifications);
      expect(h.links.calls, ['notifications']);
      expect(h.launcher.calls, isEmpty);
      expect(h.platformFake.openAppSettingsCalls, 0);
    });

    test('battery opens the OS battery settings, not the Android screens', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await h.cubit.fix(HealthKind.battery);
      expect(h.links.calls, ['battery']);
      expect(h.launcher.calls, isEmpty);
    });

    test('launch at login: fix enables it, or opens Login Items when approval is pending', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      h.launchAtLogin.current = LaunchAtLoginStatus.disabled;
      await h.cubit.fix(HealthKind.launchAtLogin);
      expect(h.launchAtLogin.sets, [true]);
      expect(h.links.calls, isEmpty);

      h.launchAtLogin.current = LaunchAtLoginStatus.requiresApproval;
      await h.cubit.fix(HealthKind.launchAtLogin);
      expect(h.links.calls, ['loginItems']);
      expect(h.launchAtLogin.sets, [true]);
    });

    test('unverified Windows notifications link to the system page', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await h.cubit.fix(HealthKind.notificationsUnverified);
      expect(h.links.calls, ['notifications']);
      expect(h.gateway.requestPermissionCalls, 0);
    });

    test('heartbeat and App Nap have no fix but still refresh', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await h.cubit.fix(HealthKind.heartbeat);
      await h.cubit.fix(HealthKind.appNap);
      expect(h.links.calls, isEmpty);
      expect(h.cubit.state.loaded, isTrue);
    });
  });
}
