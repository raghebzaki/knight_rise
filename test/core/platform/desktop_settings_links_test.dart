import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/platform/desktop_settings_links.dart';
import 'package:knight_rise/features/desktop_shell/data/macos_launch_at_login.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';

class _RecordingOpener implements UrlOpener {
  final List<Uri> opened = [];

  /// URIs that fail to open.
  final Set<String> failing = {};

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return !failing.contains(uri.toString());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _RecordingOpener opener;

  setUp(() => opener = _RecordingOpener());
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('macOS', () {
    late List<MethodCall> calls;
    late bool nativeLoginItemsWorks;
    late UrlDesktopSettingsLinks links;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      calls = [];
      nativeLoginItemsWorks = true;
      const channel = MethodChannel('test/desktop');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (!nativeLoginItemsWorks) throw PlatformException(code: 'x');
        return null;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
      );
      links = UrlDesktopSettingsLinks(opener, MacosLaunchAtLogin(channel));
    });

    test('notifications deep-links to this app, then falls back to the pane', () async {
      expect(await links.openNotifications(), isTrue);
      expect(
        opener.opened.single.toString(),
        startsWith('x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.ragheb.knightRise'),
      );

      opener.opened.clear();
      opener.failing.add(SettingsUris.macNotifications.toString());
      expect(await links.openNotifications(), isTrue);
      expect(opener.opened, [SettingsUris.macNotifications, SettingsUris.macNotificationsLegacy]);
      expect(
        SettingsUris.macNotificationsLegacy.toString(),
        'x-apple.systempreferences:com.apple.preference.notifications',
      );
    });

    test('login items use the native SMAppService call first', () async {
      expect(await links.openLoginItems(), isTrue);
      expect(calls.single.method, 'openLoginItemsSettings');
      expect(opener.opened, isEmpty);
    });

    test('login items fall back to the settings URI when the native call fails', () async {
      nativeLoginItemsWorks = false;
      expect(await links.openLoginItems(), isTrue);
      expect(opener.opened.single.toString(), 'x-apple.systempreferences:com.apple.LoginItems-Settings.extension');
    });

    test('battery', () async {
      expect(await links.openBatterySettings(), isTrue);
      expect(opener.opened.single.toString(), 'x-apple.systempreferences:com.apple.Battery-Settings.extension');
    });

    test('reports failure when nothing opens', () async {
      opener.failing.addAll([
        SettingsUris.macNotifications.toString(),
        SettingsUris.macNotificationsLegacy.toString(),
        SettingsUris.macBattery.toString(),
      ]);
      expect(await links.openNotifications(), isFalse);
      expect(await links.openBatterySettings(), isFalse);
    });
  });

  group('Windows', () {
    late UrlDesktopSettingsLinks links;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      links = UrlDesktopSettingsLinks(opener, const UnsupportedLaunchAtLogin());
    });

    test('opens the ms-settings pages', () async {
      await links.openNotifications();
      await links.openLoginItems();
      await links.openBatterySettings();
      expect(opener.opened.map((u) => u.toString()), [
        'ms-settings:notifications',
        'ms-settings:startupapps',
        'ms-settings:batterysaver',
      ]);
    });
  });

  test('mobile links are inert', () async {
    const links = UnsupportedDesktopSettingsLinks();
    expect(await links.openNotifications(), isFalse);
    expect(await links.openLoginItems(), isFalse);
    expect(await links.openBatterySettings(), isFalse);
  });
}
