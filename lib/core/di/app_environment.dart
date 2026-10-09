import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

/// Injectable environment names. A registration without an environment is
/// shared by both; one annotated [mobileEnv] or [desktopEnv] is registered only
/// when `configureDependencies` runs in that environment.
abstract final class AppEnv {
  /// Android / iOS: OS-scheduled notifications, WorkManager / BGTask safety
  /// net, background isolates.
  static const String mobile = 'mobile';

  /// macOS / Windows: one process, no background isolates; reminders are
  /// driven in-process while the app runs (launched at login).
  static const String desktop = 'desktop';
}

/// Registers only on Android / iOS.
const Environment mobileEnv = Environment(AppEnv.mobile);

/// Registers only on macOS / Windows.
const Environment desktopEnv = Environment(AppEnv.desktop);

/// True on desktop targets. Linux is not shipped, but behaves as desktop.
bool isDesktopPlatform(TargetPlatform platform) => switch (platform) {
  TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux => true,
  TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => false,
};

/// The injectable environment for [platform].
String appEnvironmentFor(TargetPlatform platform) => isDesktopPlatform(platform) ? AppEnv.desktop : AppEnv.mobile;
