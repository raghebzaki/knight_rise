import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:knight_rise/app.dart';
import 'package:knight_rise/core/config/flavor.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/scheduler/data/background_tasks.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/handle_reminder_action.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  // Must precede KnightRiseApp: its sync service reconciles on launch.
  await getIt<NotificationGateway>().initialize(onForegroundAction: _onForegroundAction);
  unawaited(getIt<BackgroundScheduler>().register());
  if (Flavor.current.isDev && kDebugMode) Bloc.observer = const _LogObserver();
  runApp(const KnightRiseApp());
}

void _onForegroundAction(ReminderAction action) {
  if (action.kind == ReminderActionKind.open) {
    debugPrint('Notification opened: $action'); // Task 7 adds navigation.
    return;
  }
  unawaited(
    getIt<HandleReminderAction>()(action).catchError((Object e, StackTrace st) {
      debugPrint('Reminder action failed: $e\n$st');
    }),
  );
}

class _LogObserver extends BlocObserver {
  const _LogObserver();

  @override
  void onTransition(Bloc<dynamic, dynamic> bloc, Transition<dynamic, dynamic> transition) {
    super.onTransition(bloc, transition);
    debugPrint('[${bloc.runtimeType}] ${transition.event.runtimeType}');
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    debugPrint('[${bloc.runtimeType}] $error\n$stackTrace');
    super.onError(bloc, error, stackTrace);
  }
}
