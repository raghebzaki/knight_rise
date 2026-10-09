import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/features/notifications/data/in_process_notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';

@module
abstract class NotificationsModule {
  @mobileEnv
  @lazySingleton
  FlutterLocalNotificationsPlugin get plugin => FlutterLocalNotificationsPlugin();

  /// Concrete desktop gateway, for the alarm clock that drains it.
  @desktopEnv
  @lazySingleton
  InProcessNotificationGateway inProcessGateway(Clock clock) => InProcessNotificationGateway(clock);

  /// The same instance as [inProcessGateway], for everything that only needs the port.
  @desktopEnv
  @lazySingleton
  NotificationGateway desktopGateway(InProcessNotificationGateway gateway) => gateway;
}
