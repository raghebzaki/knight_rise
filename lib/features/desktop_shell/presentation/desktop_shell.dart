import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/core/platform/device_locales.dart';
import 'package:knight_rise/core/platform/platform_shell.dart';
import 'package:knight_rise/core/time/location_provider.dart';
import 'package:knight_rise/features/desktop_shell/data/tray_port.dart';
import 'package:knight_rise/features/desktop_shell/data/window_port.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';
import 'package:knight_rise/features/desktop_shell/domain/tray_menu_model.dart';
import 'package:knight_rise/features/desktop_shell/presentation/app_exit.dart';
import 'package:knight_rise/features/notifications/data/notification_locale.dart';
import 'package:knight_rise/features/scheduler/desktop/desktop_alarm_clock.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';
import 'package:knight_rise/features/shield/domain/repositories/shield_repository.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Desktop window and tray: closing the window hides it (the reminder engine
/// must keep running), and the tray offers open, Shield, launch at login and
/// quit. Every step is logged and none can throw out of the shell.
@desktopEnv
@LazySingleton(as: PlatformShell)
class DesktopShell implements PlatformShell {
  DesktopShell(
    this._window,
    this._tray,
    this._launchAtLogin,
    this._alarm,
    this._shields,
    this._startShield,
    this._endShield,
    this._settings,
    this._deviceLocales,
    this._location,
    this._clock,
    this._exit,
  );

  /// Below this the phone-first layouts start to clip.
  static const Size minimumWindowSize = Size(400, 640);

  static const _macIcon = 'assets/branding/tray/tray_icon_template.png';
  static const _windowsIcon = 'assets/branding/tray/tray_icon.ico';

  final WindowPort _window;
  final TrayPort _tray;
  final LaunchAtLogin _launchAtLogin;
  final DesktopAlarmClock _alarm;
  final ShieldRepository _shields;
  final StartShield _startShield;
  final EndShield _endShield;
  final SettingsRepository _settings;
  final DeviceLocales _deviceLocales;
  final LocationProvider _location;
  final Clock _clock;
  final AppExit _exit;

  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _started = false;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _step('window init', _window.ensureInitialized);
    // Before anything else can run: from here on the close button only hides.
    await _step('prevent close', () => _window.setPreventClose(true));
    await _step('minimum size', () => _window.setMinimumSize(minimumWindowSize));
    _subscriptions.add(_window.closeRequests.listen((_) => unawaited(hideToTray())));
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    await _step('tray icon', () => _tray.setIcon(mac ? _macIcon : _windowsIcon, isTemplate: mac));
    await _step('tray tooltip', () async => await _tray.setToolTip((await _localizations()).appTitle));
    await _step('tray menu', _refreshMenu);
    _subscriptions
      ..add(_tray.clicks.listen((c) => unawaited(_step('tray click', () => _onClick(c)))))
      ..add(_tray.commands.listen((c) => unawaited(_step('tray command ${c.name}', () => _onCommand(c)))));
  }

  /// Un-minimizes first, then shows (un-hides from the tray) and focuses.
  /// Hiding and showing keep the window's bounds, so it comes back where the
  /// user left it; nothing here moves or resizes it.
  @override
  Future<void> bringToFront() async {
    await _step('restore window', () async {
      if (await _window.isMinimized()) await _window.restore();
    });
    await _step('show window', _window.show);
    await _step('focus window', _window.focus);
  }

  @override
  Future<void> hideToTray() => _step('hide to tray', _window.hide);

  Future<void> _onClick(TrayClick click) async {
    if (defaultTargetPlatform == TargetPlatform.windows && click == TrayClick.left) {
      await bringToFront();
      return;
    }
    // macOS: any click; Windows: right click. Fresh data each time it opens.
    await _refreshMenu();
    await _tray.popUp();
  }

  Future<void> _onCommand(TrayCommand command) async {
    switch (command) {
      case TrayCommand.open:
        await bringToFront();
      case TrayCommand.shield25:
        await _startShield(ShieldPreset.min25);
      case TrayCommand.shield50:
        await _startShield(ShieldPreset.min50);
      case TrayCommand.endShield:
        await _endShield();
      case TrayCommand.toggleLaunchAtLogin:
        await _launchAtLogin.setEnabled(await _launchAtLogin.status() != LaunchAtLoginStatus.enabled);
        await _refreshMenu();
      case TrayCommand.quit:
        await _step('destroy tray', _tray.destroy);
        await _step('allow close', () => _window.setPreventClose(false));
        await _exit.exit();
    }
  }

  Future<void> _refreshMenu() async {
    final l = await _localizations();
    // The first menu is built before MaterialApp's localizations have loaded
    // the date symbols the time format needs. Idempotent and cheap.
    await initializeDateFormatting(l.localeName);
    final now = _clock.now();
    final shield = await _shields.active(now);
    await _tray.setMenu(
      TrayMenuModel.build(
        l: l,
        localeName: l.localeName,
        location: _location.current,
        now: now,
        nextReminderAt: _alarm.nextFireAt,
        shieldUntil: shield?.effectiveEnd,
        launchAtLogin: await _launchAtLogin.status(),
      ),
    );
  }

  Future<AppLocalizations> _localizations() async {
    String? code;
    try {
      code = (await _settings.get()).localeCode;
    } on Object catch (e) {
      debugPrint('[shell] settings unreadable, using the device language: $e');
    }
    return lookupAppLocalizations(resolveNotificationLocale(code, _deviceLocales.current));
  }

  Future<void> _step(String name, Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (e, st) {
      debugPrint('[shell] $name failed: $e\n$st');
    }
  }
}
