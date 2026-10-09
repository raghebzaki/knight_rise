import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';
import 'package:knight_rise/features/device_health/domain/device_health_report.dart';
import 'package:knight_rise/features/device_health/domain/health_issue.dart';
import 'package:knight_rise/features/device_health/presentation/device_health_page.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

import '../../helpers/health_fakes.dart';

/// [testWidgets] that restores the platform override before the framework's
/// invariant check (which runs before tearDown callbacks).
void desktopTest(String description, Future<void> Function(WidgetTester tester) body) {
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
    required HealthPlatform platform,
    Locale locale = const Locale('en'),
    Size size = const Size(1000, 1400),
    double textScale = 1,
    void Function(HealthHarness h)? setup,
  }) async {
    debugDefaultTargetPlatformOverride = platform == HealthPlatform.windows
        ? TargetPlatform.windows
        : TargetPlatform.macOS;
    final h = HealthHarness(platform: platform);
    setup?.call(h);
    addTearDown(h.cubit.close);
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: KnightTheme.build(KnightPalette.midnight),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DeviceHealthPage(cubit: h.cubit),
      ),
    );
    await tester.pumpAndSettle();
    return h;
  }

  group('macOS', () {
    desktopTest('healthy: notifications, launch at login, background, App Nap and battery rows', (tester) async {
      await pumpPage(tester, platform: HealthPlatform.macos);
      expect(find.byKey(const Key('healthNotificationsRow')), findsOneWidget);
      expect(find.byKey(const Key('healthLaunchRow')), findsOneWidget);
      expect(find.byKey(const Key('healthBackgroundRow')), findsOneWidget);
      expect(find.byKey(const Key('healthAppNapRow')), findsOneWidget);
      expect(find.byKey(const Key('healthDesktopBatteryRow')), findsOneWidget);
      // No mobile rows.
      expect(find.byKey(const Key('healthPrecisionRow')), findsNothing);
      expect(find.byKey(const Key('healthBatteryRow')), findsNothing);
      expect(find.byKey(const Key('healthOemGuide')), findsNothing);
      expect(find.text('Allowed'), findsOneWidget);
      expect(find.text('Open notification settings'), findsOneWidget);
      expect(find.text('Knight Rise starts when you sign in'), findsOneWidget);
      expect(find.text('Running · last check just now'), findsOneWidget);
      expect(find.text('Off for Knight Rise'), findsOneWidget);
      expect(find.text('Battery saver can delay reminders on laptops.'), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(const Key('healthLaunchSwitch'))).value, isTrue);
    });

    desktopTest('blocked notifications: the link asks, then opens the notification settings', (tester) async {
      final h = await pumpPage(
        tester,
        platform: HealthPlatform.macos,
        setup: (h) => h.gateway
          ..enabled = false
          ..grantOnRequest = false,
      );
      expect(find.text('Blocked: reminders cannot appear'), findsOneWidget);
      await tester.tap(find.byKey(const Key('healthNotificationsLink')));
      await tester.pumpAndSettle();
      expect(h.gateway.requestPermissionCalls, 1);
      expect(h.links.calls, ['notifications']);
    });

    desktopTest('allowed notifications: the link opens the settings directly', (tester) async {
      final h = await pumpPage(tester, platform: HealthPlatform.macos);
      await tester.tap(find.byKey(const Key('healthNotificationsLink')));
      await tester.pumpAndSettle();
      expect(h.gateway.requestPermissionCalls, 0);
      expect(h.links.calls, ['notifications']);
    });

    desktopTest('the Launch at login switch calls setEnabled and refreshes', (tester) async {
      final h = await pumpPage(tester, platform: HealthPlatform.macos);
      await tester.tap(find.byKey(const Key('healthLaunchSwitch')));
      await tester.pumpAndSettle();
      expect(h.launchAtLogin.sets, [false]);
      expect(tester.widget<Switch>(find.byKey(const Key('healthLaunchSwitch'))).value, isFalse);
      expect(find.text('Off: reminders stop after a restart until you open the app'), findsOneWidget);
      expect(h.cubit.state.actionable.map((i) => i.kind), contains(HealthKind.launchAtLogin));

      await tester.tap(find.byKey(const Key('healthLaunchSwitch')));
      await tester.pumpAndSettle();
      expect(h.launchAtLogin.sets, [false, true]);
      expect(h.cubit.state.actionable, isEmpty);
    });

    desktopTest('requires approval explains and opens Login Items', (tester) async {
      final h = await pumpPage(
        tester,
        platform: HealthPlatform.macos,
        setup: (h) => h.launchAtLogin.current = LaunchAtLoginStatus.requiresApproval,
      );
      expect(find.text('Waiting for your approval in Login Items'), findsOneWidget);
      await tester.tap(find.text('Open Login Items'));
      await tester.pumpAndSettle();
      expect(h.links.calls, ['loginItems']);
    });

    desktopTest('unavailable disables the switch', (tester) async {
      await pumpPage(
        tester,
        platform: HealthPlatform.macos,
        setup: (h) => h.launchAtLogin.current = LaunchAtLoginStatus.unavailable,
      );
      expect(find.text('Not available in this build'), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(const Key('healthLaunchSwitch'))).onChanged, isNull);
    });

    desktopTest('a stalled heartbeat reads as a problem; App Nap on warns', (tester) async {
      await pumpPage(
        tester,
        platform: HealthPlatform.macos,
        setup: (h) {
          h.lastBeat = h.now.subtract(const Duration(minutes: 7));
          h.appNapDisabled = false;
        },
      );
      expect(find.text('Timers look throttled: last check 7 minutes ago. Reminders may be late.'), findsOneWidget);
      expect(find.text('On: macOS may delay reminders while the app is hidden'), findsOneWidget);
    });

    desktopTest('battery link opens the battery settings', (tester) async {
      final h = await pumpPage(tester, platform: HealthPlatform.macos);
      await tester.tap(find.byKey(const Key('healthBatteryLink')));
      await tester.pumpAndSettle();
      expect(h.links.calls, ['battery']);
    });

    desktopTest('resuming the app re-reads the signals', (tester) async {
      final h = await pumpPage(tester, platform: HealthPlatform.macos);
      expect(h.cubit.state.issues, isEmpty);
      h.gateway.enabled = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Blocked: reminders cannot appear'), findsOneWidget);
    });
  });

  group('Windows', () {
    desktopTest('shows the informational notifications row with a link, no App Nap row', (tester) async {
      final h = await pumpPage(tester, platform: HealthPlatform.windows);
      expect(
        find.text("Windows doesn't let apps read this. Check that notifications are on for Knight Rise."),
        findsOneWidget,
      );
      expect(find.text('Allowed'), findsNothing);
      expect(find.byKey(const Key('healthAppNapRow')), findsNothing);
      expect(find.byKey(const Key('healthLaunchRow')), findsOneWidget);
      expect(h.cubit.state.actionable, isEmpty);

      await tester.tap(find.byKey(const Key('healthNotificationsLink')));
      await tester.pumpAndSettle();
      expect(h.links.calls, ['notifications']);
      expect(h.gateway.requestPermissionCalls, 0);
    });

    desktopTest('disabled launch at login can be fixed with the switch', (tester) async {
      final h = await pumpPage(
        tester,
        platform: HealthPlatform.windows,
        setup: (h) => h.launchAtLogin.current = LaunchAtLoginStatus.disabled,
      );
      expect(h.cubit.state.actionable, hasLength(1));
      await tester.tap(find.byKey(const Key('healthLaunchSwitch')));
      await tester.pumpAndSettle();
      expect(h.launchAtLogin.sets, [true]);
      expect(h.cubit.state.actionable, isEmpty);
    });
  });

  for (final platform in [HealthPlatform.macos, HealthPlatform.windows]) {
    for (final locale in [const Locale('en'), const Locale('ar')]) {
      desktopTest('$platform ${locale.languageCode}: no overflow at 400x640 and 2x text', (tester) async {
        await pumpPage(
          tester,
          platform: platform,
          locale: locale,
          size: const Size(400, 640),
          textScale: 2,
          setup: (h) {
            h.lastBeat = h.now.subtract(const Duration(minutes: 12));
            h.launchAtLogin.current = LaunchAtLoginStatus.requiresApproval;
            h.appNapDisabled = false;
          },
        );
        expect(find.byKey(const Key('healthLaunchRow')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView), const Offset(0, -2000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('healthDesktopBatteryRow')), findsOneWidget);
      });
    }
  }

  desktopTest('Arabic copy renders', (tester) async {
    await pumpPage(tester, platform: HealthPlatform.macos, locale: const Locale('ar'));
    expect(find.text('التشغيل عند تسجيل الدخول'), findsOneWidget);
    expect(find.text('يعمل · آخر فحص الآن'), findsOneWidget);
    expect(find.text('افتح إعدادات الإشعارات'), findsOneWidget);
  });
}
