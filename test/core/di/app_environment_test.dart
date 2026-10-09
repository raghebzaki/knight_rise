import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/features/notifications/data/in_process_notification_gateway.dart';
import 'package:knight_rise/features/notifications/data/local_notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/scheduler/data/background_tasks.dart';

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
    tearDown(() async {
      await getIt.reset(dispose: false);
      debugDefaultTargetPlatformOverride = null;
    });

    test('mobile wires WorkManager and the OS notification plugin', () async {
      await configureDependencies(environment: AppEnv.mobile);
      expect(getIt<BackgroundScheduler>(), isA<WorkmanagerBackgroundScheduler>());
      expect(getIt<NotificationGateway>(), isA<LocalNotificationGateway>());
      expect(getIt.isRegistered<WorkmanagerAdapter>(), isTrue);
      expect(getIt.isRegistered<AppDatabase>(), isTrue);
    });

    test('desktop bypasses WorkManager and the plugin isolates', () async {
      await configureDependencies(environment: AppEnv.desktop);
      expect(getIt<BackgroundScheduler>(), isA<DesktopBackgroundScheduler>());
      expect(getIt<NotificationGateway>(), isA<InProcessNotificationGateway>());
      expect(getIt.isRegistered<WorkmanagerAdapter>(), isFalse);
      expect(getIt.isRegistered<FlutterLocalNotificationsPlugin>(), isFalse);
      expect(getIt.isRegistered<AppDatabase>(), isTrue);
    });

    test('defaults to the running platform', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await configureDependencies();
      expect(getIt<BackgroundScheduler>(), isA<DesktopBackgroundScheduler>());
    });
  });
}
