import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/database/app_database.dart';
import 'package:knight_rise/core/di/injection.config.dart';
import 'package:knight_rise/core/time/timezone_loader.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:timezone/timezone.dart' as tz;

final GetIt getIt = GetIt.instance;

/// Wires the UI isolate. Milestone 2 adds `bootstrapBackground()`, which
/// registers only data sources + use cases for notification / workmanager
/// isolates.
@InjectableInit()
Future<void> configureDependencies() => getIt.init();

@module
abstract class AppModule {
  @preResolve
  @singleton
  Future<tz.Location> get location => loadLocalLocation();

  @LazySingleton(dispose: closeDatabase)
  AppDatabase get database => AppDatabase.open();

  @lazySingleton
  Clock get clock => const SystemClock();

  @lazySingleton
  ReminderPlanner get planner => const ReminderPlanner();
}

FutureOr<void> closeDatabase(AppDatabase db) => db.close();
