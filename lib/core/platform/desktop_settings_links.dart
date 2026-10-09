import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/features/desktop_shell/data/macos_launch_at_login.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a URI with the operating system. A seam so tests assert the URIs.
abstract interface class UrlOpener {
  /// Hands [uri] to the OS; true when something handled it. Never throws.
  Future<bool> open(Uri uri);
}

/// [UrlOpener] backed by `url_launcher`.
///
/// macOS: `x-apple.systempreferences:` URLs are opened through NSWorkspace,
/// which needs no sandbox entitlement.
@LazySingleton(as: UrlOpener)
class LaunchUrlOpener implements UrlOpener {
  const LaunchUrlOpener();

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object catch (e) {
      debugPrint('[settings-links] opening $uri failed: $e');
      return false;
    }
  }
}

/// Deep links into the desktop OS settings screens Device health points at.
/// Every method returns whether a screen was opened and never throws.
abstract interface class DesktopSettingsLinks {
  /// This app's notification settings (macOS) or the notifications page (Windows).
  Future<bool> openNotifications();

  /// Where the user manages apps that start at sign-in.
  Future<bool> openLoginItems();

  /// Battery settings (battery saver can delay reminders on laptops).
  Future<bool> openBatterySettings();
}

/// The macOS bundle id (matches the Runner's PRODUCT_BUNDLE_IDENTIFIER).
const String kMacosBundleId = 'com.ragheb.knightRise';

/// URIs for [DesktopSettingsLinks], exposed for tests.
abstract final class SettingsUris {
  static final Uri macNotifications = Uri.parse(
    'x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=$kMacosBundleId',
  );
  static final Uri macNotificationsLegacy = Uri.parse('x-apple.systempreferences:com.apple.preference.notifications');
  static final Uri macLoginItems = Uri.parse('x-apple.systempreferences:com.apple.LoginItems-Settings.extension');
  static final Uri macBattery = Uri.parse('x-apple.systempreferences:com.apple.Battery-Settings.extension');
  static final Uri winNotifications = Uri.parse('ms-settings:notifications');
  static final Uri winStartupApps = Uri.parse('ms-settings:startupapps');
  static final Uri winBatterySaver = Uri.parse('ms-settings:batterysaver');
}

/// macOS + Windows implementation over [UrlOpener].
@desktopEnv
@LazySingleton(as: DesktopSettingsLinks)
class UrlDesktopSettingsLinks implements DesktopSettingsLinks {
  UrlDesktopSettingsLinks(this._opener, this._launchAtLogin);

  final UrlOpener _opener;
  final LaunchAtLogin _launchAtLogin;

  bool get _windows => defaultTargetPlatform == TargetPlatform.windows;

  @override
  Future<bool> openNotifications() async {
    if (_windows) return await _opener.open(SettingsUris.winNotifications);
    return await _opener.open(SettingsUris.macNotifications) || await _opener.open(SettingsUris.macNotificationsLegacy);
  }

  @override
  Future<bool> openLoginItems() async {
    if (_windows) return await _opener.open(SettingsUris.winStartupApps);
    final launch = _launchAtLogin;
    if (launch is MacosLaunchAtLogin && await launch.openSettings()) return true;
    return await _opener.open(SettingsUris.macLoginItems);
  }

  @override
  Future<bool> openBatterySettings() => _opener.open(_windows ? SettingsUris.winBatterySaver : SettingsUris.macBattery);
}

/// Mobile has no desktop settings screens; the Device health cubit still
/// takes a [DesktopSettingsLinks] and never calls it there.
@mobileEnv
@LazySingleton(as: DesktopSettingsLinks)
class UnsupportedDesktopSettingsLinks implements DesktopSettingsLinks {
  const UnsupportedDesktopSettingsLinks();

  @override
  Future<bool> openNotifications() async => false;

  @override
  Future<bool> openLoginItems() async => false;

  @override
  Future<bool> openBatterySettings() async => false;
}
