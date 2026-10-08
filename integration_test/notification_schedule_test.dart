// Milestone 3 on-device check: what the REAL notification plugin and OS scheduler
// hold must equal what the planner computes from the same repositories.
//
// Run on a connected Android device/emulator or an iPhone (not on the host):
//
//     flutter test integration_test/notification_schedule_test.dart -d <device>
//
// Notes:
// * Run it during work hours (per the saved work schedule); otherwise it is
//   skipped with a message. It uses the app's real database and DI graph and
//   changes nothing stored except a short Shield, which it ends again.
// * Notifications must be allowed. On Android 13+ grant it up front:
//   `adb shell pm grant com.ragheb.knight_rise android.permission.POST_NOTIFICATIONS`.
//   Without permission the test is skipped.
// * Not part of `flutter test` (CI); `flutter analyze` does cover it.
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/time/local_day.dart';
import 'package:knight_rise/features/notifications/domain/notification_gateway.dart';
import 'package:knight_rise/features/routines/domain/repositories/routine_repository.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/repositories/reminder_event_repository.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/scheduler/domain/services/schedule_reconciler.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:knight_rise/features/settings/domain/repositories/settings_repository.dart';
import 'package:knight_rise/features/shield/domain/repositories/shield_repository.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/day_override_repository.dart';
import 'package:knight_rise/features/work_hours/domain/repositories/work_schedule_repository.dart';
import 'package:timezone/timezone.dart' as tz;

/// One pending reminder reduced to what is compared.
typedef _Entry = ({int id, int fireAtMs, bool recovery});

String _show(_Entry e) =>
    '#${e.id} ${DateTime.fromMillisecondsSinceEpoch(e.fireAtMs)}${e.recovery ? ' (recovery)' : ''}';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late NotificationGateway gateway;
  late ScheduleReconciler reconciler;
  late Clock clock;
  late tz.Location location;
  late RoutineRepository routines;
  late WorkScheduleRepository work;
  late SettingsRepository settings;
  late ReminderEventRepository events;
  late ShieldRepository shields;
  late DayOverrideRepository overrides;

  Future<List<_Entry>> osPending() async {
    final pending = await gateway.pendingReminders();
    return [
      for (final p in pending)
        if (p.id >= kReservedNotificationIdLimit && p.payload != null)
          (id: p.id, fireAtMs: p.payload!.fireAt.millisecondsSinceEpoch, recovery: p.payload!.recovery),
    ]..sort((a, b) => a.fireAtMs != b.fireAtMs ? a.fireAtMs.compareTo(b.fireAtMs) : a.id.compareTo(b.id));
  }

  /// The planner recomputed from the same repositories at this moment.
  Future<List<_Entry>> expectedPlan() async {
    final now = clock.now();
    final dayStart = startOfLocalDay(now, location);
    final plan = const ReminderPlanner().plan(
      PlannerInput(
        routines: await routines.getAll(),
        schedule: await work.get(),
        location: location,
        now: now,
        history: historyFromEvents(await events.getSince(dayStart)),
        shields: [for (final s in await shields.getSince(dayStart)) s.toWindow()],
        recoverOnExit: (await settings.get()).shieldRecoverOnExit,
        overrides: await overrides.getFrom(localDateOf(now, location)),
      ),
    );
    return [
      for (final r in plan) (id: r.notificationId, fireAtMs: r.fireAt.millisecondsSinceEpoch, recovery: r.recovery),
    ]..sort((a, b) => a.fireAtMs != b.fireAtMs ? a.fireAtMs.compareTo(b.fireAtMs) : a.id.compareTo(b.id));
  }

  Future<void> expectOsMatchesPlanner(String when) async {
    final expected = await expectedPlan();
    final actual = await osPending();
    expect(actual.map((e) => e.id).toSet(), expected.map((e) => e.id).toSet(), reason: '$when: id sets differ');
    expect(actual.map(_show).toList(), expected.map(_show).toList(), reason: '$when: fire times differ');
  }

  Future<bool> statusShown() async {
    final active = await FlutterLocalNotificationsPlugin().getActiveNotifications();
    return active.any((n) => n.id == kShieldStatusNotificationId);
  }

  testWidgets('pending OS notifications equal the planner through Shield start and end', (tester) async {
    await configureDependencies();
    gateway = getIt<NotificationGateway>();
    reconciler = getIt<ScheduleReconciler>();
    clock = getIt<Clock>();
    location = getIt<tz.Location>();
    routines = getIt<RoutineRepository>();
    work = getIt<WorkScheduleRepository>();
    settings = getIt<SettingsRepository>();
    events = getIt<ReminderEventRepository>();
    shields = getIt<ShieldRepository>();
    overrides = getIt<DayOverrideRepository>();

    await gateway.initialize(onForegroundAction: (_) {});
    if (!await gateway.notificationsEnabled()) {
      await gateway.requestPermission();
    }
    if (!await gateway.notificationsEnabled()) {
      markTestSkipped('Notifications are not allowed for Knight Rise; grant the permission and rerun.');
      return;
    }

    try {
      // --- Baseline: a manual reconcile, then OS list == planner.
      var run = await reconciler.reconcile(ReconcileTrigger.manual);
      expect(run.error, isNull);

      // Starting a Shield needs work hours right now; skip gracefully otherwise.
      final probe = getIt<StartShield>();
      final session = await probe(ShieldPreset.min25);
      if (session == null) {
        markTestSkipped('Not inside work hours right now (or no work window today); run again during work hours.');
        return;
      }
      // Undo the probe so the baseline is measured without a Shield.
      await getIt<EndShield>()();
      run = await reconciler.reconcile(ReconcileTrigger.configChange);
      expect(run.error, isNull);
      await expectOsMatchesPlanner('baseline');
      final baseline = await osPending();
      expect(baseline.any((e) => e.id < kReservedNotificationIdLimit), isFalse);

      // --- Start a 25 min Shield: nothing pending inside it; recovery if anything was suppressed.
      final shield = (await getIt<StartShield>()(ShieldPreset.min25))!;
      run = await reconciler.reconcile(ReconcileTrigger.configChange);
      expect(run.error, isNull);
      await expectOsMatchesPlanner('Shield active');
      final during = await osPending();
      final startMs = shield.startAt.millisecondsSinceEpoch;
      final endMs = shield.endAt.millisecondsSinceEpoch;
      expect(
        during.where((e) => !e.recovery && e.fireAtMs >= startMs && e.fireAtMs < endMs),
        isEmpty,
        reason: 'no regular reminder may be pending inside the Shield',
      );
      final suppressed = baseline.any((e) => e.fireAtMs >= startMs && e.fireAtMs < endMs);
      if (suppressed) {
        expect(during.where((e) => e.recovery), isNotEmpty, reason: 'a slot was suppressed, so a recovery is due');
      }
      expect(await statusShown(), isTrue, reason: 'the ongoing Shield status notification is shown');
      expect(await gateway.pendingIds(), isNot(contains(kShieldStatusNotificationId)));

      // --- End it: status cleared, pending list equals the planner again.
      await getIt<EndShield>()();
      run = await reconciler.reconcile(ReconcileTrigger.configChange);
      expect(run.error, isNull);
      await expectOsMatchesPlanner('Shield ended');
      expect(await statusShown(), isFalse, reason: 'the status notification is cleared');
      expect(await gateway.pendingIds(), isNot(contains(kShieldStatusNotificationId)));

      // --- A resume reconcile is a no-op.
      final again = await reconciler.reconcile(ReconcileTrigger.resume);
      expect(again.added, 0);
      expect(again.cancelled, 0);
    } finally {
      // Leave no Shield behind and a schedule that matches the stored config.
      if (await shields.active(clock.now()) != null) await getIt<EndShield>()();
      await reconciler.reconcile(ReconcileTrigger.configChange);
    }
  });
}
