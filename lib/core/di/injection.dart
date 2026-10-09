import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/core/di/injection.config.dart';
import 'package:knight_rise/core/time/timezone_loader.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:timezone/timezone.dart' as tz;

final GetIt getIt = GetIt.instance;

/// Wires the current isolate (UI, or a mobile background isolate via
/// `bootstrapBackground()`). [environment] defaults to the running platform's
/// ([AppEnv.mobile] or [AppEnv.desktop]); see [appEnvironmentFor].
@InjectableInit()
Future<void> configureDependencies({String? environment}) =>
    getIt.init(environment: environment ?? appEnvironmentFor(defaultTargetPlatform));

@module
abstract class AppModule {
  @preResolve
  @singleton
  Future<tz.Location> get location => loadLocalLocation();

  @mobileEnv
  @LazySingleton(dispose: closeDatabase)
  AppDatabase get mobileDatabase => AppDatabase.open();

  @desktopEnv
  @LazySingleton(dispose: closeDatabase)
  AppDatabase get desktopDatabase => AppDatabase.openDesktop();

  @lazySingleton
  Clock get clock => const SystemClock();

  @lazySingleton
  ReminderPlanner get planner => const ReminderPlanner();
}

FutureOr<void> closeDatabase(AppDatabase db) => db.close();
