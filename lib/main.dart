import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:knight_rise/app.dart';
import 'package:knight_rise/core/config/flavor.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/router/break_location.dart';
import 'package:knight_rise/core/widgets/knight_error_view.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/onboarding/presentation/onboarding_gate.dart';
import 'package:knight_rise/features/scheduler/data/background_tasks.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/handle_reminder_action.dart';
import 'package:knight_rise/features/settings/presentation/locale_cubit.dart';
import 'package:knight_rise/features/splash/presentation/animated_splash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  // Must precede KnightRiseApp: its sync service reconciles on launch.
  await getIt<NotificationGateway>().initialize(onForegroundAction: _onForegroundAction);
  unawaited(getIt<BackgroundScheduler>().register());
  // The router redirects on it, so it must be known before the first frame.
  await getIt<OnboardingGate>().load();
  if (kDevFlavor && kDebugMode) Bloc.observer = const _LogObserver();
  if (kReleaseMode) ErrorWidget.builder = (_) => const KnightBuildErrorFallback();
  // So the first frame is already in the chosen language and direction.
  await getIt<LocaleCubit>().load();
  // Cold start from a notification tap: the plugin reports it as launch
  // details instead of calling the foreground callback. Read before the first
  // frame (the native splash is still up) so such a launch skips the splash.
  final launch = await getIt<NotificationGateway>().launchAction();
  runApp(KnightRiseApp(showSplash: SplashOverlay.playsOnLaunch(launch)));
  if (launch != null && launch.kind == ReminderActionKind.open) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _openBreak(launch));
  }
}

final _openBreakDeduper = OpenBreakDeduper();

void _openBreak(ReminderAction action) {
  if (!_openBreakDeduper.shouldOpen(action.notificationId)) return;
  unawaited(getIt<GoRouter>().push(breakLocation(action.types)));
}

void _onForegroundAction(ReminderAction action) {
  if (action.kind == ReminderActionKind.open) {
    _openBreak(action);
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
