/// Static app metadata. Keep [kAppVersion] in sync with `pubspec.yaml`.
const String kAppVersion = '1.0.0';

/// Android application id (see `android/app/build.gradle`).
const String kAndroidPackageName = 'com.ragheb.knight_rise';

/// Route names reserved for screens that ship later.
abstract final class ReservedRoutes {
  /// Device health screen (`DeviceHealthPage`).
  static const String deviceHealth = '/settings/device-health';
}
