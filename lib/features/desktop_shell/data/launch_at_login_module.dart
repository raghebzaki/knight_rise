import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/features/desktop_shell/data/macos_launch_at_login.dart';
import 'package:knight_rise/features/desktop_shell/data/windows_launch_at_login.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';

@module
abstract class LaunchAtLoginModule {
  /// The implementation for the running desktop OS.
  @desktopEnv
  @lazySingleton
  LaunchAtLogin get launchAtLogin => launchAtLoginFor(defaultTargetPlatform);
}

/// Chooses the [LaunchAtLogin] implementation for [platform].
LaunchAtLogin launchAtLoginFor(TargetPlatform platform) => switch (platform) {
  TargetPlatform.macOS => MacosLaunchAtLogin(),
  TargetPlatform.windows => WindowsLaunchAtLogin(),
  _ => const UnsupportedLaunchAtLogin(),
};
