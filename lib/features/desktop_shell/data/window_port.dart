import 'dart:async';
import 'dart:ui' show Size;

import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:window_manager/window_manager.dart';

/// The native window, behind a seam (the only user of `window_manager`).
abstract interface class WindowPort {
  Future<void> ensureInitialized();

  /// Turns the close button into a [closeRequests] event instead of quitting.
  // ignore: avoid_positional_boolean_parameters
  Future<void> setPreventClose(bool v);
  Future<void> show();
  Future<void> focus();
  Future<void> hide();
  Future<bool> isVisible();

  /// Whether the window is minimized (to the taskbar / Dock).
  Future<bool> isMinimized();

  /// Un-minimizes the window at its previous size and position.
  Future<void> restore();

  Future<void> setMinimumSize(Size size);
  Future<void> destroy();

  /// Emits when the user tries to close the window while close is prevented.
  Stream<void> get closeRequests;
}

@desktopEnv
@LazySingleton(as: WindowPort)
class WindowManagerPort with WindowListener implements WindowPort {
  WindowManagerPort() {
    windowManager.addListener(this);
  }

  final _close = StreamController<void>.broadcast();

  @override
  Stream<void> get closeRequests => _close.stream;

  @override
  void onWindowClose() => _close.add(null);

  @override
  Future<void> ensureInitialized() => windowManager.ensureInitialized();

  @override
  Future<void> setPreventClose(bool v) => windowManager.setPreventClose(v);

  @override
  Future<void> show() => windowManager.show();

  @override
  Future<void> focus() => windowManager.focus();

  @override
  Future<void> hide() => windowManager.hide();

  @override
  Future<bool> isVisible() => windowManager.isVisible();

  @override
  Future<bool> isMinimized() => windowManager.isMinimized();

  @override
  Future<void> restore() => windowManager.restore();

  @override
  Future<void> setMinimumSize(Size size) => windowManager.setMinimumSize(size);

  @override
  Future<void> destroy() => windowManager.destroy();
}
