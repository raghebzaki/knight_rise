import 'package:knight_rise/core/platform/system_settings_launcher.dart';

/// Records the settings screens it was asked to open.
class FakeSystemSettingsLauncher implements SystemSettingsLauncher {
  final List<String> channelCalls = [];

  /// Every call in order, e.g. `notifications`, `battery`, `details`, `component:<name>`.
  final List<String> calls = [];

  /// Components that "exist"; [openComponent] returns false for others.
  Set<String> availableComponents = {};

  /// What the intent-based openers return.
  bool intentsSucceed = true;

  @override
  Future<void> openChannelSettings(String channelId) async => channelCalls.add(channelId);

  @override
  Future<bool> openAppNotificationSettings() async {
    calls.add('notifications');
    return intentsSucceed;
  }

  @override
  Future<bool> openBatteryOptimizationSettings() async {
    calls.add('battery');
    return intentsSucceed;
  }

  @override
  Future<bool> openAppDetailsSettings() async {
    calls.add('details');
    return true;
  }

  @override
  Future<bool> openComponent(String componentName) async {
    calls.add('component:$componentName');
    return availableComponents.contains(componentName);
  }
}
