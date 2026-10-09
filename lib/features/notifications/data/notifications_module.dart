import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/di/app_environment.dart';

@module
abstract class NotificationsModule {
  @mobileEnv
  @lazySingleton
  FlutterLocalNotificationsPlugin get plugin => FlutterLocalNotificationsPlugin();
}
