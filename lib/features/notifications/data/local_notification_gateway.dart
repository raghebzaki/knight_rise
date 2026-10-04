import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/config/background_ids.dart';
import 'package:knight_rise/features/notifications/data/background_entry.dart';
import 'package:knight_rise/features/notifications/data/notification_content.dart';
import 'package:knight_rise/features/notifications/data/notification_response_mapper.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/pending_reminder.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/notifications/domain/reminder_payload.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';
import 'package:timezone/timezone.dart' as tz;

/// Brand cyan. Mirrors `KnightPalette.primary`; duplicated because `core/theme`
/// is the only place hex literals are allowed and the gateway must run in
/// background isolates without a theme.
const Color _brandCyan = Color(0xFF00E5FF);

const String _groupKey = 'knight_rise';

@LazySingleton(as: NotificationGateway)
class LocalNotificationGateway implements NotificationGateway {
  LocalNotificationGateway(this._plugin, this._location);

  final FlutterLocalNotificationsPlugin _plugin;
  final tz.Location _location;

  Future<void>? _initFuture;
  void Function(ReminderAction action)? _onForegroundAction;

  AppLocalizations get _l10n => NotificationCopy.defaultL10n;

  @override
  Future<void> initialize({required void Function(ReminderAction action) onForegroundAction}) {
    // Always use the latest callback, but only initialise the plugin once.
    _onForegroundAction = onForegroundAction;
    return _initFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    final l = _l10n;
    final settings = InitializationSettings(
      android: const AndroidInitializationSettings(androidNotificationIcon),
      iOS: DarwinInitializationSettings(
        // Permissions are requested explicitly via requestPermission().
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [
          DarwinNotificationCategory(
            NotificationActionIds.iosCategory,
            actions: [
              // No `foreground` option: Done / Snooze run without opening the app.
              DarwinNotificationAction.plain(NotificationActionIds.done, l.done),
              DarwinNotificationAction.plain(NotificationActionIds.snooze, l.snooze10),
            ],
          ),
        ],
      ),
    );
    await _pluginInitialize(settings);
    await _createChannels(l);
  }

  Future<void> _pluginInitialize(InitializationSettings settings) async {
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _handleForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: knightNotificationBackgroundHandler,
    );
  }

  Future<void> _createChannels(AppLocalizations l) async {
    final android = _android;
    if (android == null) return;
    for (final t in RoutineType.values) {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          NotificationCopy.channelId(t),
          NotificationCopy.routineLabel(l, t),
          description: NotificationCopy.channelDescription(l, t),
          importance: Importance.high,
        ),
      );
    }
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        NotificationChannelIds.system,
        l.notifChannelSystemName,
        description: l.notifChannelSystemDescription,
        importance: Importance.low,
      ),
    );
  }

  void _handleForegroundResponse(NotificationResponse response) {
    final action = reminderActionFromResponse(response);
    if (action != null) _onForegroundAction?.call(action);
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  @override
  Future<void> schedule(PlannedReminder reminder, {required bool exact}) =>
      _scheduleWithId(reminder.notificationId, reminder, exact: exact);

  @override
  Future<void> scheduleTest({required DateTime at}) => _scheduleWithId(
    kTestNotificationId,
    PlannedReminder(fireAt: at, types: const {RoutineType.hydration}),
    exact: false,
  );

  Future<void> _scheduleWithId(int id, PlannedReminder reminder, {required bool exact}) async {
    final l = _l10n;
    final content = NotificationCopy.build(reminder.types, l10n: l);
    final channelId = NotificationCopy.channelFor(reminder.types);
    final primary = NotificationCopy.sortedTypes(reminder.types).first;
    await _pluginZonedSchedule(
      id: id,
      title: content.title,
      body: content.body,
      when: tz.TZDateTime.from(reminder.fireAt, _location),
      details: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          NotificationCopy.routineLabel(l, primary),
          channelDescription: NotificationCopy.channelDescription(l, primary),
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          color: _brandCyan,
          styleInformation: BigTextStyleInformation(content.body),
          groupKey: _groupKey,
          actions: [
            AndroidNotificationAction(NotificationActionIds.done, l.done),
            AndroidNotificationAction(NotificationActionIds.snooze, l.snooze10),
          ],
        ),
        iOS: DarwinNotificationDetails(
          categoryIdentifier: NotificationActionIds.iosCategory,
          threadIdentifier: channelId,
          interruptionLevel: InterruptionLevel.active,
        ),
      ),
      mode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: ReminderPayload.of(reminder).encode(),
    );
  }

  Future<void> _pluginZonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required NotificationDetails details,
    required AndroidScheduleMode mode,
    required String payload,
  }) => _plugin.zonedSchedule(
    id: id,
    title: title,
    body: body,
    scheduledDate: when,
    notificationDetails: details,
    androidScheduleMode: mode,
    payload: payload,
  );

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAllPendingNotifications();

  @override
  Future<Set<int>> pendingIds() async {
    final pending = await _plugin.pendingNotificationRequests();
    return {for (final p in pending) p.id};
  }

  @override
  Future<List<PendingReminder>> pendingReminders() async {
    final pending = await _plugin.pendingNotificationRequests();
    return [for (final p in pending) PendingReminder(id: p.id, payload: ReminderPayload.tryDecode(p.payload))];
  }

  @override
  Future<bool> notificationsEnabled() async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return await _android?.areNotificationsEnabled() ?? false;
      case TargetPlatform.iOS:
        return (await _ios?.checkPermissions())?.isEnabled ?? false;
      case TargetPlatform.macOS:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return true;
    }
  }

  @override
  Future<bool> requestPermission() async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return await _android?.requestNotificationsPermission() ?? false;
      case TargetPlatform.iOS:
        return await _ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      case TargetPlatform.macOS:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return false;
    }
  }

  @override
  Future<bool> canScheduleExact() async => await _android?.canScheduleExactNotifications() ?? true;

  @override
  Future<ReminderAction?> launchAction() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details == null || !details.didNotificationLaunchApp || response == null) return null;
    return reminderActionFromResponse(response);
  }
}
