import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/device_health/domain/device_health_report.dart';
import 'package:knight_rise/features/device_health/presentation/device_health_page.dart';

import '../../helpers/health_fakes.dart';
import '../../helpers/pump_app.dart';

/// [testWidgets] that restores the platform override before the framework's
/// invariant check (which runs before tearDown callbacks).
void healthTest(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  Future<HealthHarness> pumpPage(
    WidgetTester tester, {
    HealthPlatform platform = HealthPlatform.android,
    String maker = 'Google Pixel',
    void Function(HealthHarness h)? setup,
  }) async {
    debugDefaultTargetPlatformOverride = platform == HealthPlatform.ios ? TargetPlatform.iOS : TargetPlatform.android;
    final h = HealthHarness(platform: platform, manufacturer: maker);
    setup?.call(h);
    addTearDown(h.cubit.close);
    useTallView(tester);
    await tester.pumpWidget(themedApp(DeviceHealthPage(cubit: h.cubit)));
    await tester.pumpAndSettle();
    return h;
  }

  healthTest('Android: shows notification, precision and battery rows plus the generic guide; no fixes when healthy', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text('Device health'), findsOneWidget);
    expect(find.byKey(const Key('healthNotificationsRow')), findsOneWidget);
    expect(find.byKey(const Key('healthPrecisionRow')), findsOneWidget);
    expect(find.byKey(const Key('healthBatteryRow')), findsOneWidget);
    expect(find.byKey(const Key('healthBackgroundRefreshRow')), findsNothing);
    expect(find.text('Fire reminders on the exact minute. Uses more battery.'), findsOneWidget);
    expect(find.text('Allowed'), findsOneWidget);
    expect(find.text('Unrestricted'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Fix'), findsNothing);
    expect(find.text('Android battery settings'), findsOneWidget);
    expect(find.text('More: dontkillmyapp.com'), findsOneWidget);
  });

  healthTest('Android: Fix buttons appear for notifications and battery and run the fixes', (tester) async {
    final h = await pumpPage(
      tester,
      maker: 'Xiaomi Redmi',
      setup: (h) {
        h.gateway
          ..enabled = false
          ..grantOnRequest = false;
        h.platformFake.ignoringBattery = false;
      },
    );
    expect(find.widgetWithText(FilledButton, 'Fix'), findsNWidgets(2));
    expect(find.text('Blocked: reminders cannot appear'), findsOneWidget);
    expect(find.text('Optimized: the system may delay reminders'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byKey(const Key('healthBatteryRow')), matching: find.text('Fix')));
    await tester.pumpAndSettle();
    expect(h.launcher.calls, ['battery']);

    await tester.tap(find.descendant(of: find.byKey(const Key('healthNotificationsRow')), matching: find.text('Fix')));
    await tester.pumpAndSettle();
    expect(h.gateway.requestPermissionCalls, 1);
    expect(h.launcher.calls, ['battery', 'notifications']);
  });

  healthTest('Android: shows the numbered guide of the detected maker and Open settings tries its screen', (
    tester,
  ) async {
    final h = await pumpPage(tester, maker: 'samsung samsung');
    expect(find.text('Samsung'), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('3.'), findsOneWidget);
    expect(find.text('Open Never sleeping apps and add Knight Rise.'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('healthOpenSettings')));
    await tester.tap(find.byKey(const Key('healthOpenSettings')));
    await tester.pumpAndSettle();
    expect(h.launcher.calls.first, startsWith('component:com.samsung.android.lool/'));
    expect(h.launcher.calls.last, 'details');
  });

  healthTest('Precision switch asks for the permission first and flips on after returning', (tester) async {
    final h = await pumpPage(tester, setup: (h) => h.gateway.exactAllowed = false);
    expect(tester.widget<Switch>(find.byKey(const Key('healthPrecisionSwitch'))).value, isFalse);

    await tester.tap(find.byKey(const Key('healthPrecisionSwitch')));
    await tester.pumpAndSettle();
    expect(h.gateway.requestExactAlarmPermissionCalls, 1);
    expect(h.settings.current.precisionTiming, isFalse);

    h.gateway.exactAllowed = true;
    await h.cubit.refresh();
    await tester.pumpAndSettle();
    expect(h.settings.current.precisionTiming, isTrue);
    expect(tester.widget<Switch>(find.byKey(const Key('healthPrecisionSwitch'))).value, isTrue);

    await tester.tap(find.byKey(const Key('healthPrecisionSwitch')));
    await tester.pumpAndSettle();
    expect(h.settings.current.precisionTiming, isFalse);
  });

  healthTest('Precision on without the permission shows a Fix button', (tester) async {
    final h = await pumpPage(
      tester,
      setup: (h) {
        h.gateway.exactAllowed = false;
        unawaited(h.settings.save(h.settings.current.copyWith(precisionTiming: true)));
      },
    );
    expect(find.text('Needs the Alarms & reminders permission'), findsOneWidget);
    await tester.tap(find.byKey(const Key('healthPrecisionFix')));
    await tester.pumpAndSettle();
    expect(h.gateway.requestExactAlarmPermissionCalls, 1);
  });

  healthTest('iOS: shows Background App Refresh, no battery, precision or OEM guide', (tester) async {
    final h = await pumpPage(
      tester,
      platform: HealthPlatform.ios,
      setup: (h) => h.platformFake.refresh = BackgroundRefresh.denied,
    );
    expect(find.byKey(const Key('healthBackgroundRefreshRow')), findsOneWidget);
    expect(find.byKey(const Key('healthBatteryRow')), findsNothing);
    expect(find.byKey(const Key('healthPrecisionRow')), findsNothing);
    expect(find.byKey(const Key('healthOemGuide')), findsNothing);
    expect(find.text('Off: your schedule may not be topped up'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Fix'));
    await tester.pumpAndSettle();
    expect(h.platformFake.openAppSettingsCalls, 1);
  });
}
