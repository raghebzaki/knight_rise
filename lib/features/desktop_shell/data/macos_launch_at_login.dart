import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';

/// macOS: `SMAppService` through the runner's `knight_rise/desktop` channel.
class MacosLaunchAtLogin implements LaunchAtLogin {
  MacosLaunchAtLogin([MethodChannel? channel]) : _channel = channel ?? const MethodChannel('knight_rise/desktop');

  final MethodChannel _channel;

  @override
  Future<LaunchAtLoginStatus> status() => _status('launchAtLoginStatus');

  @override
  Future<LaunchAtLoginStatus> setEnabled(bool enabled) => _status('setLaunchAtLogin', {'enabled': enabled});

  @override
  Future<bool> launchedAtLogin() async {
    try {
      return await _channel.invokeMethod<bool>('launchedAtLogin') ?? false;
    } on Object catch (e) {
      debugPrint('[launch-at-login] launchedAtLogin failed: $e');
      return false;
    }
  }

  /// Opens System Settings > Login Items, where the user approves a pending
  /// registration. Best effort.
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openLoginItemsSettings');
    } on Object catch (e) {
      debugPrint('[launch-at-login] openLoginItemsSettings failed: $e');
    }
  }

  Future<LaunchAtLoginStatus> _status(String method, [Object? arguments]) async {
    try {
      final raw = await _channel.invokeMethod<String>(method, arguments);
      return switch (raw) {
        'enabled' => LaunchAtLoginStatus.enabled,
        'notRegistered' => LaunchAtLoginStatus.disabled,
        'requiresApproval' => LaunchAtLoginStatus.requiresApproval,
        _ => LaunchAtLoginStatus.unavailable,
      };
    } on MissingPluginException {
      return LaunchAtLoginStatus.unavailable;
    } on Object catch (e) {
      debugPrint('[launch-at-login] $method failed: $e');
      return LaunchAtLoginStatus.unavailable;
    }
  }
}
