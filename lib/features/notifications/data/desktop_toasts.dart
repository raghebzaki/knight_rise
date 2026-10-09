import 'dart:async';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/config/background_ids.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/core/platform/device_locales.dart';
import 'package:knight_rise/features/notifications/data/desktop_toast_codec.dart';
import 'package:knight_rise/features/notifications/data/notification_locale.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';
import 'package:path/path.dart' as p;

/// macOS / Windows toast backend: the only place the desktop side of
/// `flutter_local_notifications` is touched, so tests mock this class.
///
/// Toasts are shown immediately ([show]); scheduling stays in the app process
/// (see `InProcessNotificationGateway`). Every method degrades to a logged
/// no-op or a permissive default when the platform backend is missing.
@desktopEnv
@lazySingleton
class DesktopToasts {
  DesktopToasts(this._plugin, this._settings, this._deviceLocales);

  final FlutterLocalNotificationsPlugin _plugin;
  final SettingsRepository _settings;
  final DeviceLocales _deviceLocales;
  Future<void>? _initFuture;

  /// Sets the plugin up once ([onResponse] of the first call wins).
  Future<void> initialize(void Function(NotificationResponse response) onResponse) =>
      _initFuture ??= _initialize(onResponse);

  Future<void> _initialize(void Function(NotificationResponse response) onResponse) async {
    try {
      final l = lookupAppLocalizations(await _locale());
      await _plugin.initialize(
        settings: InitializationSettings(
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
            notificationCategories: [
              DarwinNotificationCategory(
                NotificationActionIds.iosCategory,
                actions: [
                  DarwinNotificationAction.plain(NotificationActionIds.done, l.done),
                  DarwinNotificationAction.plain(NotificationActionIds.snooze, l.snooze10),
                ],
              ),
            ],
          ),
          windows: WindowsInitializationSettings(
            appName: 'Knight Rise',
            appUserModelId: kWindowsAppUserModelId,
            guid: kWindowsToastActivatorGuid,
            iconPath: _iconPath(),
          ),
        ),
        onDidReceiveNotificationResponse: onResponse,
      );
    } on Object catch (e, st) {
      debugPrint('Toast backend init failed: $e\n$st');
    }
  }

  Future<Locale> _locale() async {
    String? code;
    try {
      code = (await _settings.get()).localeCode;
    } on Object catch (e) {
      debugPrint('Toast locale: settings unreadable: $e');
    }
    return resolveNotificationLocale(code, _deviceLocales.current);
  }

  /// The bundled mark next to the executable (Windows layout), if present.
  static String? _iconPath() {
    try {
      final path = p.join(
        File(Platform.resolvedExecutable).parent.path,
        'data',
        'flutter_assets',
        'assets',
        'branding',
        'splash_mark.png',
      );
      return File(path).existsSync() ? path : null;
    } on Object {
      return null;
    }
  }

  /// Shows a toast now. The action buttons come back through the
  /// `onResponse` given to [initialize], encoded by [encodeToastArgument].
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
    required String doneLabel,
    required String snoozeLabel,
  }) async {
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: encodeToastArgument('', payload),
        notificationDetails: NotificationDetails(
          macOS: const DarwinNotificationDetails(
            categoryIdentifier: NotificationActionIds.iosCategory,
            threadIdentifier: 'knight_rise',
            presentBanner: true,
            presentList: true,
            presentSound: true,
          ),
          windows: WindowsNotificationDetails(
            actions: [
              WindowsAction(content: doneLabel, arguments: encodeToastArgument(NotificationActionIds.done, payload)),
              WindowsAction(
                content: snoozeLabel,
                arguments: encodeToastArgument(NotificationActionIds.snooze, payload),
              ),
            ],
          ),
        ),
      );
    } on Object catch (e, st) {
      debugPrint('Showing toast $id failed: $e\n$st');
    }
  }

  /// Asks macOS for permission; Windows needs none.
  Future<bool> requestPermission() async {
    try {
      final macOS = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      if (macOS == null) return true;
      return await macOS.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    } on Object catch (e) {
      debugPrint('Toast permission request failed: $e');
      return false;
    }
  }

  /// Whether macOS currently lets the app show notifications; always true
  /// elsewhere.
  Future<bool> notificationsEnabled() async {
    try {
      final macOS = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      if (macOS == null) return true;
      return (await macOS.checkPermissions())?.isEnabled ?? false;
    } on Object catch (e) {
      debugPrint('Toast permission check failed: $e');
      return false;
    }
  }

  /// The toast response that cold-started the app, or null.
  Future<NotificationResponse?> launchResponse() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      return (details?.didNotificationLaunchApp ?? false) ? details?.notificationResponse : null;
    } on Object catch (e) {
      debugPrint('Toast launch details failed: $e');
      return null;
    }
  }
}
