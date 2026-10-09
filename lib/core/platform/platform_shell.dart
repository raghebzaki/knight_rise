import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/di/app_environment.dart';

/// The desktop window and tray integration, behind a seam so mobile and tests
/// carry none of it. The desktop implementation is `DesktopShell`.
abstract interface class PlatformShell {
  /// Sets up the window and the tray. Idempotent; never throws.
  Future<void> start();

  /// Shows and focuses the main window, un-hiding it if it was sent to the
  /// tray. Never throws.
  Future<void> bringToFront();

  /// Hides the main window to the tray (the keyboard shortcut for the close
  /// button). Nothing on mobile. Never throws.
  Future<void> hideToTray();
}

/// Mobile: there is no window or tray to manage.
@mobileEnv
@LazySingleton(as: PlatformShell)
class NoopPlatformShell implements PlatformShell {
  const NoopPlatformShell();

  @override
  Future<void> start() async {}

  @override
  Future<void> bringToFront() async {}

  @override
  Future<void> hideToTray() async {}
}
