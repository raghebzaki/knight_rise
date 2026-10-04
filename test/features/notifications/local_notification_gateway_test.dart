import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/features/notifications/data/background_entry.dart';
import 'package:knight_rise/features/notifications/data/local_notification_gateway.dart';
import 'package:knight_rise/features/notifications/data/notification_response_mapper.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/notifications/domain/reminder_payload.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/tz.dart';

class MockPlugin extends Mock implements FlutterLocalNotificationsPlugin;

class MockAndroid extends Mock implements AndroidFlutterLocalNotificationsPlugin;

class MockIos extends Mock implements IOSFlutterLocalNotificationsPlugin;

void main() {
  late MockPlugin plugin;
  late MockAndroid android;
  late MockIos ios;
  late LocalNotificationGateway gateway;
  final location = cairo;
  final fireAt = DateTime.utc(2026, 10, 5, 7, 30);

  setUpAll(() {
    registerFallbackValue(const InitializationSettings());
    registerFallbackValue(const NotificationDetails());
    registerFallbackValue(tz.TZDateTime.utc(2026));
    registerFallbackValue(AndroidScheduleMode.inexact);
    registerFallbackValue(const AndroidNotificationChannel('a', 'b'));
  });

  setUp(() {
    plugin = MockPlugin();
    android = MockAndroid();
    ios = MockIos();
    when(() => plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>())
        .thenReturn(android);
    when(() => plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()).thenReturn(ios);
    when(() => android.canScheduleExactNotifications()).thenAnswer((_) async => true);
    when(() => android.createNotificationChannel(any())).thenAnswer((_) async {});
    when(
      () => plugin.initialize(
        settings: any(named: 'settings'),
        onDidReceiveNotificationResponse: any(named: 'onDidReceiveNotificationResponse'),
        onDidReceiveBackgroundNotificationResponse: any(named: 'onDidReceiveBackgroundNotificationResponse'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => plugin.zonedSchedule(
        id: any(named: 'id'),
        scheduledDate: any(named: 'scheduledDate'),
        notificationDetails: any(named: 'notificationDetails'),
        androidScheduleMode: any(named: 'androidScheduleMode'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async {});
    gateway = LocalNotificationGateway(plugin, location);
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  ({int id, tz.TZDateTime when, NotificationDetails details, AndroidScheduleMode mode, String? payload})
  captureSchedule() {
    final c = verify(
      () => plugin.zonedSchedule(
        id: captureAny(named: 'id'),
        scheduledDate: captureAny(named: 'scheduledDate'),
        notificationDetails: captureAny(named: 'notificationDetails'),
        androidScheduleMode: captureAny(named: 'androidScheduleMode'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        payload: captureAny(named: 'payload'),
      ),
    ).captured;
    return (
      id: c[0] as int,
      when: c[1] as tz.TZDateTime,
      details: c[2] as NotificationDetails,
      mode: c[3] as AndroidScheduleMode,
      payload: c[4] as String?,
    );
  }

  group('schedule', () {
    test('passes id, zoned time, payload, channel and actions', () async {
      final r = PlannedReminder(fireAt: fireAt, types: const {RoutineType.hydration});
      await gateway.schedule(r, exact: false);
      final s = captureSchedule();
      expect(s.id, r.notificationId);
      expect(s.when.location, location);
      expect(s.when.isAtSameMomentAs(fireAt), isTrue);
      expect(s.payload, ReminderPayload.of(r).encode());
      expect(s.mode, AndroidScheduleMode.inexactAllowWhileIdle);
      final a = s.details.android!;
      expect(a.channelId, 'hydration');
      expect(a.importance, Importance.high);
      expect(a.priority, Priority.high);
      expect(a.category, AndroidNotificationCategory.reminder);
      expect(a.groupKey, 'knight_rise');
      expect(a.styleInformation, isA<BigTextStyleInformation>());
      expect(a.actions!.map((x) => x.id), ['done', 'snooze']);
      expect(a.actions!.every((x) => !x.showsUserInterface && x.cancelNotification), isTrue);
      final i = s.details.iOS!;
      expect(i.categoryIdentifier, 'knight_reminder');
      expect(i.threadIdentifier, 'hydration');
      expect(i.interruptionLevel, InterruptionLevel.active);
    });

    test('exact when requested', () async {
      await gateway.schedule(PlannedReminder(fireAt: fireAt, types: const {RoutineType.stretch}), exact: true);
      expect(captureSchedule().mode, AndroidScheduleMode.exactAllowWhileIdle);
    });

    test('does not query exact-alarm permission itself', () async {
      await gateway.schedule(PlannedReminder(fireAt: fireAt, types: const {RoutineType.stretch}), exact: true);
      verifyNever(() => android.canScheduleExactNotifications());
    });

    test('merged {stretch, eyeRest} uses the stretch channel', () async {
      await gateway.schedule(
        PlannedReminder(fireAt: fireAt, types: const {RoutineType.eyeRest, RoutineType.stretch}),
        exact: false,
      );
      final a = captureSchedule().details.android!;
      expect(a.channelId, 'stretch');
    });
  });

  group('initialize', () {
    test('creates channels, registers callbacks once, no permission prompts', () async {
      await gateway.initialize(onForegroundAction: (_) {});
      await gateway.initialize(onForegroundAction: (_) {});
      final c = verify(
        () => plugin.initialize(
          settings: captureAny(named: 'settings'),
          onDidReceiveNotificationResponse: any(named: 'onDidReceiveNotificationResponse'),
          onDidReceiveBackgroundNotificationResponse: captureAny(named: 'onDidReceiveBackgroundNotificationResponse'),
        ),
      )..called(1);
      final settings = c.captured[0] as InitializationSettings;
      expect(settings.android!.defaultIcon, 'ic_stat_knight');
      final d = settings.iOS!;
      expect(d.requestAlertPermission, isFalse);
      expect(d.requestBadgePermission, isFalse);
      expect(d.requestSoundPermission, isFalse);
      final cat = d.notificationCategories.single;
      expect(cat.identifier, 'knight_reminder');
      expect(cat.actions.map((a) => a.identifier), ['done', 'snooze']);
      expect(cat.actions.every((a) => !a.options.contains(DarwinNotificationActionOption.foreground)), isTrue);
      expect(c.captured[1], same(knightNotificationBackgroundHandler));

      final channels = verify(() => android.createNotificationChannel(captureAny())).captured
          .cast<AndroidNotificationChannel>();
      expect(channels.map((x) => x.id), ['hydration', 'stretch', 'eye_rest', 'system']);
      expect(channels.map((x) => x.importance), [Importance.high, Importance.high, Importance.high, Importance.low]);
    });

    test('foreground response invokes the callback', () async {
      ReminderAction? got;
      await gateway.initialize(onForegroundAction: (a) => got = a);
      final cb =
          verify(
                () => plugin.initialize(
                  settings: any(named: 'settings'),
                  onDidReceiveNotificationResponse: captureAny(named: 'onDidReceiveNotificationResponse'),
                  onDidReceiveBackgroundNotificationResponse: any(named: 'onDidReceiveBackgroundNotificationResponse'),
                ),
              ).captured.single
              as DidReceiveNotificationResponseCallback;
      cb(_response('done', _payload()));
      expect(got?.kind, ReminderActionKind.done);
      got = null;
      cb(_response(null, 'garbage'));
      expect(got, isNull);
    });
  });

  group('misc plugin calls', () {
    test('pendingIds maps ids', () async {
      when(() => plugin.pendingNotificationRequests()).thenAnswer(
        (_) async => const [
          PendingNotificationRequest(1, null, null, null),
          PendingNotificationRequest(7, 't', 'b', 'p'),
        ],
      );
      expect(await gateway.pendingIds(), {1, 7});
    });

    test('cancel and cancelAll delegate', () async {
      when(() => plugin.cancel(id: any(named: 'id'))).thenAnswer((_) async {});
      when(() => plugin.cancelAllPendingNotifications()).thenAnswer((_) async {});
      await gateway.cancel(5);
      await gateway.cancelAll();
      verify(() => plugin.cancel(id: 5)).called(1);
      verify(() => plugin.cancelAllPendingNotifications()).called(1);
    });

    test('requestPermission per platform', () async {
      when(() => android.requestNotificationsPermission()).thenAnswer((_) async => true);
      when(() => ios.requestPermissions(alert: true, badge: true, sound: true)).thenAnswer((_) async => false);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await gateway.requestPermission(), isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await gateway.requestPermission(), isFalse);
      verify(() => ios.requestPermissions(alert: true, badge: true, sound: true)).called(1);
    });

    test('notificationsEnabled per platform', () async {
      when(() => android.areNotificationsEnabled()).thenAnswer((_) async => false);
      when(() => ios.checkPermissions()).thenAnswer((_) async => _iosOptions(enabled: true));
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await gateway.notificationsEnabled(), isFalse);
      when(() => android.areNotificationsEnabled()).thenAnswer((_) async => true);
      expect(await gateway.notificationsEnabled(), isTrue);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await gateway.notificationsEnabled(), isTrue);
      when(() => ios.checkPermissions()).thenAnswer((_) async => _iosOptions(enabled: false));
      expect(await gateway.notificationsEnabled(), isFalse);
      when(() => ios.checkPermissions()).thenAnswer((_) async => null);
      expect(await gateway.notificationsEnabled(), isFalse);

      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(await gateway.notificationsEnabled(), isTrue);
    });

    test('notificationsEnabled is false without a platform implementation', () async {
      when(() => plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>())
          .thenReturn(null);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await gateway.notificationsEnabled(), isFalse);
    });

    test('pendingReminders decodes payloads; unknown or missing payloads are null', () async {
      final r = PlannedReminder(fireAt: fireAt, types: const {RoutineType.hydration, RoutineType.eyeRest});
      when(() => plugin.pendingNotificationRequests()).thenAnswer(
        (_) async => [
          PendingNotificationRequest(10, 't', 'b', ReminderPayload.of(r).encode()),
          const PendingNotificationRequest(11, null, null, null),
          const PendingNotificationRequest(12, null, null, 'garbage'),
        ],
      );
      final got = await gateway.pendingReminders();
      expect(got.map((p) => p.id), [10, 11, 12]);
      expect(got[0].payload, ReminderPayload.of(r));
      expect(got[0].payload!.types, r.types);
      expect(got[0].payload!.fireAt.isAtSameMomentAs(fireAt), isTrue);
      expect(got[1].payload, isNull);
      expect(got[2].payload, isNull);
    });

    test('scheduleTest uses the reserved id, hydration content and inexact timing', () async {
      await gateway.scheduleTest(at: fireAt);
      final s = captureSchedule();
      expect(s.id, kTestNotificationId);
      expect(s.id, lessThan(kReservedNotificationIdLimit));
      expect(s.when.isAtSameMomentAs(fireAt), isTrue);
      expect(s.mode, AndroidScheduleMode.inexactAllowWhileIdle);
      expect(s.details.android!.channelId, 'hydration');
      final payload = ReminderPayload.tryDecode(s.payload)!;
      expect(payload.types, {RoutineType.hydration});
      expect(payload.fireAt.isAtSameMomentAs(fireAt), isTrue);
    });

    test('canScheduleExact true when no android implementation', () async {
      when(() => plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>())
          .thenReturn(null);
      expect(await gateway.canScheduleExact(), isTrue);
    });

    test('launchAction only when the notification launched the app', () async {
      when(() => plugin.getNotificationAppLaunchDetails())
          .thenAnswer((_) async => const NotificationAppLaunchDetails(false));
      expect(await gateway.launchAction(), isNull);
      when(
        () => plugin.getNotificationAppLaunchDetails(),
      ).thenAnswer((_) async => NotificationAppLaunchDetails(true, notificationResponse: _response(null, _payload())));
      expect((await gateway.launchAction())?.kind, ReminderActionKind.open);
    });
  });

  group('response mapping', () {
    test('done / snooze / open / bad', () {
      final p = ReminderPayload.tryDecode(_payload())!;
      for (final (id, kind) in [
        ('done', ReminderActionKind.done),
        ('snooze', ReminderActionKind.snooze),
        (null, ReminderActionKind.open),
        ('', ReminderActionKind.open),
      ]) {
        final a = reminderActionFromResponse(_response(id, _payload(), nid: 42))!;
        expect(a.kind, kind);
        expect(a.types, p.types);
        expect(a.notificationId, 42);
        expect(a.scheduledAt.isAtSameMomentAs(fireAt), isTrue);
      }
      expect(reminderActionFromResponse(_response('weird', _payload())), isNull);
      expect(reminderActionFromResponse(_response('done', 'junk')), isNull);
      expect(reminderActionFromResponse(_response('done', null)), isNull);
      expect(
        reminderActionFromResponse(
          NotificationResponse(
            notificationResponseType: NotificationResponseType.notificationDismissed,
            payload: _payload(),
          ),
        ),
        isNull,
      );
    });

    test('falls back to the deterministic id when the response has none', () {
      final a = reminderActionFromResponse(_response('done', _payload()))!;
      expect(a.notificationId, PlannedReminder(fireAt: fireAt, types: const {RoutineType.hydration}).notificationId);
    });
  });
}

String _payload() =>
    ReminderPayload(types: const {RoutineType.hydration}, fireAt: DateTime.utc(2026, 10, 5, 7, 30)).encode();

NotificationResponse _response(String? actionId, String? payload, {int? nid}) => NotificationResponse(
  notificationResponseType: actionId == null || actionId.isEmpty
      ? NotificationResponseType.selectedNotification
      : NotificationResponseType.selectedNotificationAction,
  id: nid,
  actionId: actionId,
  payload: payload,
);

NotificationsEnabledOptions _iosOptions({required bool enabled}) => NotificationsEnabledOptions(
  isEnabled: enabled,
  isSoundEnabled: enabled,
  isAlertEnabled: enabled,
  isBadgeEnabled: enabled,
  isProvisionalEnabled: false,
  isCriticalEnabled: false,
  isProvidesAppNotificationSettingsEnabled: false,
);
