import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:knight_rise/core/config/background_ids.dart';
import 'package:knight_rise/core/di/app_environment.dart';
import 'package:knight_rise/core/di/bootstrap_background.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/features/quest_log/domain/usecases/history_usecases.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/services/schedule_reconciler.dart';
import 'package:workmanager/workmanager.dart';

/// Period of the safety-net reconcile (Android's minimum is 15 min; see ARCHITECTURE.md section 3).
const Duration reconcileInterval = Duration(hours: 1);

/// WorkManager entry point, run in a headless isolate. Referenced by
/// [WorkmanagerBackgroundScheduler.register] via `Workmanager().initialize`.
@pragma('vm:entry-point')
void knightCallbackDispatcher() {
  Workmanager().executeTask(
    (task, inputData) => runBackgroundTask(
      task,
      bootstrap: bootstrapBackground,
      reconciler: () async => getIt<ScheduleReconciler>(),
      maintainHistory: () => getIt<MaintainHistory>()(),
    ),
  );
}

/// Testable core of the WorkManager callback. Never throws.
///
/// Returns `false` only when [bootstrap] fails, so WorkManager retries with
/// backoff. Any failure after bootstrap (including a run that recorded an
/// error) returns `true`: the next periodic wake-up retries anyway and we
/// don't want OS retry storms.
///
/// After the reconcile, [maintainHistory] finalizes past days and prunes old
/// data (Milestone 4); its failure is logged and never affects the result.
///
/// The task name is only logged: Android passes [BackgroundIds.reconcileTaskName]
/// while iOS passes the BGTask identifier, and both mean "reconcile".
Future<bool> runBackgroundTask(
  String task, {
  required Future<void> Function() bootstrap,
  required Future<ScheduleReconciler> Function() reconciler,
  required Future<void> Function() maintainHistory,
}) async {
  debugPrint('[background] task "$task" started');
  try {
    await bootstrap();
  } on Object catch (e, st) {
    debugPrint('[background] bootstrap failed for "$task": $e\n$st');
    return false;
  }
  try {
    final run = await (await reconciler()).reconcile(ReconcileTrigger.periodic);
    if (run.error != null) debugPrint('[background] reconcile recorded an error: ${run.error}');
  } on Object catch (e, st) {
    debugPrint('[background] reconcile threw for "$task": $e\n$st');
  }
  try {
    await maintainHistory();
  } on Object catch (e, st) {
    debugPrint('[background] history maintenance failed for "$task": $e\n$st');
  }
  return true;
}

/// Thin seam over the static-ish `Workmanager()` singleton so it can be mocked.
abstract interface class WorkmanagerAdapter {
  Future<void> initialize(Function callbackDispatcher);

  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    required Duration frequency,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
  });
}

@mobileEnv
@LazySingleton(as: WorkmanagerAdapter)
class DefaultWorkmanagerAdapter implements WorkmanagerAdapter {
  const DefaultWorkmanagerAdapter();

  @override
  Future<void> initialize(Function callbackDispatcher) => Workmanager().initialize(callbackDispatcher);

  @override
  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    required Duration frequency,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
  }) => Workmanager().registerPeriodicTask(
    uniqueName,
    taskName,
    frequency: frequency,
    initialDelay: initialDelay,
    constraints: constraints,
    existingWorkPolicy: existingWorkPolicy,
    backoffPolicy: backoffPolicy,
    backoffPolicyDelay: backoffPolicyDelay,
  );
}

/// Registers the periodic reconcile safety net. Safe to call on every launch.
abstract interface class BackgroundScheduler {
  /// Idempotent; logs instead of throwing so app start never fails.
  Future<void> register();
}

/// Mobile: WorkManager (Android) / BGAppRefresh (iOS) wakes a headless isolate
/// that runs [knightCallbackDispatcher].
@mobileEnv
@LazySingleton(as: BackgroundScheduler)
class WorkmanagerBackgroundScheduler implements BackgroundScheduler {
  WorkmanagerBackgroundScheduler(this._workmanager);

  final WorkmanagerAdapter _workmanager;

  @override
  Future<void> register() async {
    try {
      // `isInDebugMode` is deprecated in workmanager 0.10 (no effect), so omitted.
      await _workmanager.initialize(knightCallbackDispatcher);
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          await _workmanager.registerPeriodicTask(
            BackgroundIds.androidReconcileUniqueName,
            BackgroundIds.reconcileTaskName,
            frequency: reconcileInterval,
            // `update` changes the spec in place and preserves the original
            // period timing, so relaunching does not push the next run back
            // (`replace` would reset it), yet a changed frequency still applies
            // in later releases (`keep` would ignore it).
            existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
            constraints: Constraints(networkType: NetworkType.notRequired),
            backoffPolicy: BackoffPolicy.exponential,
            backoffPolicyDelay: const Duration(minutes: 5),
          );
        case TargetPlatform.iOS:
          // The native side only registers the BGTask launch handler
          // (AppDelegate); Dart must submit the BGAppRefreshTaskRequest.
          // The unique name is the BGTask identifier. `initialDelay` maps to
          // earliestBeginDate; the plugin ignores frequency on iOS.
          await _workmanager.registerPeriodicTask(
            BackgroundIds.iosReconcileTask,
            BackgroundIds.reconcileTaskName,
            frequency: reconcileInterval,
            initialDelay: reconcileInterval,
          );
        case TargetPlatform.fuchsia || TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows:
          break;
      }
    } on Object catch (e, st) {
      debugPrint('[background] WorkManager registration failed: $e\n$st');
    }
  }
}

/// Desktop: there is no OS background wake-up and no headless isolate. The
/// app process itself stays alive (launched at login) and reconciles
/// in-process, so there is nothing to register.
@desktopEnv
@LazySingleton(as: BackgroundScheduler)
class DesktopBackgroundScheduler implements BackgroundScheduler {
  const DesktopBackgroundScheduler();

  @override
  Future<void> register() async {}
}
