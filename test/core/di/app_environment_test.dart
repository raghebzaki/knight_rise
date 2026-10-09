import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/features/notifications/data/in_process_notification_gateway.dart';
import 'package:knight_rise/features/notifications/data/local_notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/reminder_presenter.dart';
import 'package:knight_rise/features/scheduler/data/background_tasks.dart';
import 'package:knight_rise/features/scheduler/desktop/desktop_alarm_clock.dart';
import 'package:knight_rise/features/scheduler/desktop/desktop_heartbeat.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('desktop platforms map to the desktop environment', () {
    expect(appEnvironmentFor(TargetPlatform.macOS), AppEnv.desktop);
    expect(appEnvironmentFor(TargetPlatform.windows), AppEnv.desktop);
    expect(appEnvironmentFor(TargetPlatform.linux), AppEnv.desktop);
    expect(appEnvironmentFor(TargetPlatform.android), AppEnv.mobile);
    expect(appEnvironmentFor(TargetPlatform.iOS), AppEnv.mobile);
    expect(appEnvironmentFor(TargetPlatform.fuchsia), AppEnv.mobile);
  });

  group('configureDependencies', () {
    /// Wires [environment], then swaps the platform database for an in-memory
    /// one: the desktop scheduler reaches it through the heartbeat's sync
    /// service, and opening the real one needs path_provider.
    Future<void> configure([String? environment]) async {
      await configureDependencies(environment: environment);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      getIt
        ..unregister<AppDatabase>()
        ..registerSingleton<AppDatabase>(db);
    }

    tearDown(() async {
      await getIt.reset(dispose: false);
      debugDefaultTargetPlatformOverride = null;
    });

    test('mobile wires WorkManager and the OS notification plugin', () async {
      await configure(AppEnv.mobile);
      expect(getIt<BackgroundScheduler>(), isA<WorkmanagerBackgroundScheduler>());
      expect(getIt<NotificationGateway>(), isA<LocalNotificationGateway>());
      expect(getIt.isRegistered<WorkmanagerAdapter>(), isTrue);
      expect(getIt.isRegistered<AppDatabase>(), isTrue);
    });

    test('desktop bypasses WorkManager and the plugin isolates', () async {
      await configure(AppEnv.desktop);
      expect(getIt<BackgroundScheduler>(), isA<DesktopBackgroundScheduler>());
      expect(getIt<NotificationGateway>(), isA<InProcessNotificationGateway>());
      expect(getIt.isRegistered<WorkmanagerAdapter>(), isFalse);
      expect(getIt.isRegistered<FlutterLocalNotificationsPlugin>(), isFalse);
      expect(getIt.isRegistered<AppDatabase>(), isTrue);
    });

    test('desktop wires the reminder engine around one shared gateway', () async {
      await configure(AppEnv.desktop);
      expect(getIt<DesktopHeartbeat>(), isNotNull);
      expect(getIt<DesktopAlarmClock>(), isNotNull);
      expect(getIt<ReminderPresenter>(), isNotNull);
      expect(identical(getIt<NotificationGateway>(), getIt<InProcessNotificationGateway>()), isTrue);
    });

    test('mobile does not register the desktop reminder engine', () async {
      await configure(AppEnv.mobile);
      expect(getIt.isRegistered<DesktopHeartbeat>(), isFalse);
      expect(getIt.isRegistered<DesktopAlarmClock>(), isFalse);
      expect(getIt.isRegistered<ReminderPresenter>(), isFalse);
      expect(getIt.isRegistered<InProcessNotificationGateway>(), isFalse);
    });

    test('defaults to the running platform', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await configure();
      expect(getIt<BackgroundScheduler>(), isA<DesktopBackgroundScheduler>());
    });
  });
}
