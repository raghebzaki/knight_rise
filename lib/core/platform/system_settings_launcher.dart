import 'package:android_intent_plus/android_intent.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/config/app_info.dart';

/// Opens OS settings screens. Faked in widget tests; Device health extends it.
abstract interface class SystemSettingsLauncher {
  /// Android notification-channel settings (sound, vibration) for [channelId].
  Future<void> openChannelSettings(String channelId);

  /// Android app notification settings. Returns whether an activity was started.
  Future<bool> openAppNotificationSettings();

  /// Android battery-optimization list. Returns whether an activity was started.
  Future<bool> openBatteryOptimizationSettings();

  /// Android "App info" page for this app. Returns whether an activity was started.
  Future<bool> openAppDetailsSettings();

  /// Starts an OEM settings activity given as `package/fully.qualified.Class`.
  /// Returns false when it does not exist or is not accessible.
  Future<bool> openComponent(String componentName);
}

@LazySingleton(as: SystemSettingsLauncher)
class AndroidSystemSettingsLauncher implements SystemSettingsLauncher {
  const AndroidSystemSettingsLauncher();

  @override
  Future<void> openChannelSettings(String channelId) => AndroidIntent(
    action: 'android.settings.CHANNEL_NOTIFICATION_SETTINGS',
    arguments: <String, Object>{
      'android.provider.extra.APP_PACKAGE': kAndroidPackageName,
      'android.provider.extra.CHANNEL_ID': channelId,
    },
  ).launch();

  @override
  Future<bool> openAppNotificationSettings() => _launch(
    const AndroidIntent(
      action: 'android.settings.APP_NOTIFICATION_SETTINGS',
      arguments: <String, Object>{'android.provider.extra.APP_PACKAGE': kAndroidPackageName},
    ),
  );

  @override
  Future<bool> openBatteryOptimizationSettings() =>
      _launch(const AndroidIntent(action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS'));

  @override
  Future<bool> openAppDetailsSettings() => _launch(
    const AndroidIntent(action: 'android.settings.APPLICATION_DETAILS_SETTINGS', data: 'package:$kAndroidPackageName'),
  );

  @override
  Future<bool> openComponent(String componentName) {
    final slash = componentName.indexOf('/');
    return _launch(
      AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: slash > 0 ? componentName.substring(0, slash) : null,
        componentName: componentName.substring(slash + 1),
      ),
    );
  }

  Future<bool> _launch(AndroidIntent intent) async {
    try {
      await intent.launch();
      return true;
    } on Object {
      return false;
    }
  }
}
