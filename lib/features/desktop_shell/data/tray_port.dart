import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/features/desktop_shell/domain/tray_menu_model.dart';
import 'package:tray_manager/tray_manager.dart';

/// Which mouse button hit the tray icon.
enum TrayClick { left, right }

/// The system tray, behind a seam (the only user of `tray_manager`).
abstract interface class TrayPort {
  /// [assetPath] is a Flutter asset path; [isTemplate] (macOS) lets the OS tint it.
  Future<void> setIcon(String assetPath, {bool isTemplate});
  Future<void> setToolTip(String text);
  Future<void> setMenu(List<TrayMenuEntry> entries);

  /// Shows the menu at the icon.
  Future<void> popUp();
  Future<void> destroy();

  /// Menu items the user chose.
  Stream<TrayCommand> get commands;

  /// Icon clicks (mouse down).
  Stream<TrayClick> get clicks;
}

@desktopEnv
@LazySingleton(as: TrayPort)
class TrayManagerPort with TrayListener implements TrayPort {
  TrayManagerPort() {
    trayManager.addListener(this);
  }

  final _commands = StreamController<TrayCommand>.broadcast();
  final _clicks = StreamController<TrayClick>.broadcast();

  @override
  Stream<TrayCommand> get commands => _commands.stream;

  @override
  Stream<TrayClick> get clicks => _clicks.stream;

  @override
  void onTrayIconMouseDown() => _clicks.add(TrayClick.left);

  @override
  void onTrayIconRightMouseDown() => _clicks.add(TrayClick.right);

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    for (final c in TrayCommand.values) {
      if (c.name == key) {
        _commands.add(c);
        return;
      }
    }
  }

  @override
  Future<void> setIcon(String assetPath, {bool isTemplate = false}) =>
      trayManager.setIcon(assetPath, isTemplate: isTemplate);

  @override
  Future<void> setToolTip(String text) => trayManager.setToolTip(text);

  @override
  Future<void> setMenu(List<TrayMenuEntry> entries) => trayManager.setContextMenu(
    Menu(
      items: [
        for (final e in entries)
          if (e.isSeparator)
            MenuItem.separator()
          else if (e.checked != null)
            MenuItem.checkbox(key: e.command?.name, label: e.label, checked: e.checked, disabled: !e.enabled)
          else
            MenuItem(key: e.command?.name, label: e.label, disabled: !e.enabled),
      ],
    ),
  );

  @override
  Future<void> popUp() => trayManager.popUpContextMenu();

  @override
  Future<void> destroy() => trayManager.destroy();
}
