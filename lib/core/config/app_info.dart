import 'package:knight_rise/core/config/flavor.dart';

/// Static app metadata. Keep [kAppVersion] in sync with `pubspec.yaml`.
const String kAppVersion = '1.0.0';

/// Android application id of this build (see `android/app/build.gradle.kts`):
/// the dev flavor appends `.dev`. Used by the system-settings intents, which
/// must open this app's own pages.
const String kAndroidPackageName = kDevFlavor ? 'com.ragheb.knight_rise.dev' : 'com.ragheb.knight_rise';

/// Route names reserved for screens that ship later.
abstract final class ReservedRoutes {
  /// Device health screen (`DeviceHealthPage`).
  static const String deviceHealth = '/settings/device-health';
}
