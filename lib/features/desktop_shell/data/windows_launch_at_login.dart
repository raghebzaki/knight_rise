import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:knight_rise/core/platform/launch_arguments.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';
import 'package:win32_registry/win32_registry.dart';

/// The `Run` key's values, so tests never touch win32.
abstract interface class RunKeyStore {
  /// The string value [name], or null when absent.
  String? read(String name);

  void write(String name, String value);

  /// Removes [name]; absent is fine.
  void delete(String name);
}

/// HKCU `Software\Microsoft\Windows\CurrentVersion\Run`.
class RegistryRunKeyStore implements RunKeyStore {
  const RegistryRunKeyStore();

  static const _path = r'Software\Microsoft\Windows\CurrentVersion\Run';

  RegistryKey _open({required bool write}) => RegistryKey.openCurrentUser().open(
    _path,
    config: RegistryOpenConfig(access: write ? RegistryAccess.readWrite : RegistryAccess.read, create: write),
  );

  @override
  String? read(String name) {
    final key = _open(write: false);
    try {
      final value = key.getValue(name);
      return value is StringValue ? value.value : null;
    } finally {
      key.close();
    }
  }

  @override
  void write(String name, String value) {
    final key = _open(write: true);
    try {
      key.setValue(name, RegistryValue.string(value));
    } finally {
      key.close();
    }
  }

  @override
  void delete(String name) {
    final key = _open(write: true);
    try {
      key.removeValue(name);
    } finally {
      key.close();
    }
  }
}

/// Windows: a per-user `Run` entry that starts the app with `--autostart`.
///
/// Not usable from an MSIX-packaged build (HKCU is virtualized there).
class WindowsLaunchAtLogin implements LaunchAtLogin {
  WindowsLaunchAtLogin({this._store = const RegistryRunKeyStore(), String? executable})
    : _executable = executable ?? Platform.resolvedExecutable;

  /// Registry value name.
  static const valueName = 'KnightRise';

  final RunKeyStore _store;
  final String _executable;

  /// What the entry must hold: the quoted executable plus the autostart flag.
  String get expectedCommand => '"$_executable" --autostart';

  /// Enabled only when the stored command is exactly [expectedCommand]; a path
  /// left by a moved install counts as disabled and is rewritten on enable.
  @override
  Future<LaunchAtLoginStatus> status() async {
    try {
      return _store.read(valueName) == expectedCommand ? LaunchAtLoginStatus.enabled : LaunchAtLoginStatus.disabled;
    } on Object catch (e) {
      debugPrint('[launch-at-login] reading the Run key failed: $e');
      return LaunchAtLoginStatus.unavailable;
    }
  }

  @override
  Future<LaunchAtLoginStatus> setEnabled(bool enabled) async {
    try {
      if (enabled) {
        _store.write(valueName, expectedCommand);
      } else {
        _store.delete(valueName);
      }
    } on Object catch (e) {
      debugPrint('[launch-at-login] writing the Run key failed: $e');
      return LaunchAtLoginStatus.unavailable;
    }
    return await status();
  }

  @override
  Future<bool> launchedAtLogin() async => LaunchArguments.autostart;
}
