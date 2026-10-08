import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/features/cycle/presentation/bloc/cycle_bloc.dart';
import 'package:knight_rise/features/cycle/presentation/pages/home_page.dart';
import 'package:knight_rise/features/notifications/presentation/notification_permission_cubit.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reconcile_run.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:knight_rise/features/scheduler/presentation/schedule_sync_service.dart';
import 'package:knight_rise/features/settings/presentation/theme_cubit.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:knight_rise/features/shield/presentation/shield_cubit.dart';
import 'package:knight_rise/features/work_hours/domain/usecases/day_override_usecases.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';
import '../../helpers/health_fakes.dart';
import '../../helpers/tz.dart';

ShieldCubit _shieldCubit(Clock clock) {
  final shields = FakeShieldRepository();
  final overrides = FakeDayOverrideRepository();
  final location = FakeLocationProvider(cairo);
  return ShieldCubit(
    StartShield(shields, FakeWorkScheduleRepository(), overrides, const ReminderPlanner(), clock, location),
    ExtendShield(shields, clock),
    EndShield(shields, clock),
    SetDayOff(overrides),
    ExtendWorkDay(overrides),
    ClearDayOverride(overrides),
    clock,
    location,
  );
}

void main() {
  Future<FakeReminderEventRepository> pumpHome(
    WidgetTester tester,
    DateTime now, {
    FakeNotificationGateway? gateway,
    FakeScheduleReconciler? reconciler,
    HealthHarness? health,
    RemindersPausedSource? paused,
  }) async {
    final events = FakeReminderEventRepository();
    final settings = FakeSettingsRepository();
    final clock = FixedClock(now);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepositoryProvider<Clock>.value(
        value: clock,
        child: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => ThemeCubit(settings)),
            BlocProvider(
              create: (_) {
                final cubit = NotificationPermissionCubit(
                  gateway ?? FakeNotificationGateway(),
                  reconciler ?? FakeScheduleReconciler(),
                );
                unawaited(cubit.check());
                return cubit;
              },
            ),
            BlocProvider(
              create: (_) => CycleBloc(
                WatchCycleInputs(
                  FakeRoutineRepository(),
                  FakeWorkScheduleRepository(),
                  events,
                  settings,
                  FakeShieldRepository(),
                  FakeDayOverrideRepository(),
                ),
                const BuildCycleSnapshot(ReminderPlanner()),
                CompleteRoutine(events, settings, clock),
                SnoozeRoutine(events, clock, cairo),
                clock,
                cairo,
              )..add(const CycleStarted()),
            ),
          ],
          child: MaterialApp(
            theme: KnightTheme.build(KnightPalette.midnight),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: HomePage(
              shieldCubitFactory: () => _shieldCubit(clock),
              deviceHealthCubitFactory: health == null ? null : () => health.cubit,
              pausedSource: paused,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return events;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('shows the quest, a due routine, and claims the break', (tester) async {
    final events = await pumpHome(tester, at(cairo, 2026, 10, 5, 9, 50));

    expect(find.text('KNIGHT RISE'), findsOneWidget);
    expect(find.text("TODAY'S QUEST"), findsOneWidget);
    expect(find.text('DUE NOW'), findsOneWidget);
    expect(find.text('Hydration'), findsWidgets);

    await tester.tap(find.text('Claim break'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // At 09:50 both hydration (09:45) and eye rest (09:20/09:40) are due.
    expect(events.all, hasLength(2));
    expect(events.all.where((e) => e.type == RoutineType.hydration && e.outcome == ReminderOutcome.done), hasLength(1));
    expect(events.all.where((e) => e.type == RoutineType.eyeRest && e.outcome == ReminderOutcome.done), hasLength(1));
    expect(find.text('250 ml today'), findsOneWidget);
    expect(find.text('NEXT UP'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('off duty on the weekend', (tester) async {
    await pumpHome(tester, at(cairo, 2026, 10, 10, 12)); // Saturday
    expect(find.text('Off duty'), findsWidgets);
    expect(find.textContaining('Back on duty'), findsOneWidget);
    await unmount(tester);
  });

  group('notification permission card', () {
    final now = at(cairo, 2026, 10, 5, 9, 50);

    testWidgets('hidden while notifications are enabled', (tester) async {
      await pumpHome(tester, now);
      expect(find.text('Enable reminders'), findsNothing);
      expect(find.text('Enable'), findsNothing);
      await unmount(tester);
    });

    testWidgets('shown when disabled; no system prompt until Enable is tapped', (tester) async {
      final gateway = FakeNotificationGateway()..enabled = false;
      await pumpHome(tester, now, gateway: gateway);

      expect(find.text('Enable reminders'), findsOneWidget);
      expect(find.text('Knight Rise needs notifications to call you to your breaks.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Enable'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Not now'), findsOneWidget);
      expect(gateway.requestPermissionCalls, 0);
      await unmount(tester);
    });

    testWidgets('Not now hides it for the session', (tester) async {
      final gateway = FakeNotificationGateway()..enabled = false;
      await pumpHome(tester, now, gateway: gateway);

      await tester.tap(find.text('Not now'));
      await tester.pump();

      expect(find.text('Enable reminders'), findsNothing);
      expect(gateway.requestPermissionCalls, 0);
      await unmount(tester);
    });

    testWidgets('Enable -> granted: card disappears and the schedule is armed', (tester) async {
      final gateway = FakeNotificationGateway()..enabled = false;
      final reconciler = FakeScheduleReconciler();
      await pumpHome(tester, now, gateway: gateway, reconciler: reconciler);

      await tester.tap(find.text('Enable'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(gateway.requestPermissionCalls, 1);
      expect(reconciler.calls, [ReconcileTrigger.manual]);
      expect(find.text('Enable reminders'), findsNothing);
      await unmount(tester);
    });

    testWidgets('Enable -> refused: body points to system settings', (tester) async {
      final gateway = FakeNotificationGateway()
        ..enabled = false
        ..grantOnRequest = false;
      await pumpHome(tester, now, gateway: gateway);

      await tester.tap(find.text('Enable'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Enable reminders'), findsOneWidget);
      expect(find.text('Notifications are off. Turn them on in system settings.'), findsOneWidget);
      expect(find.text('Knight Rise needs notifications to call you to your breaks.'), findsNothing);
      await unmount(tester);
    });
  });

  testWidgets('dev builds show the diagnostics entry next to the gallery', (tester) async {
    await pumpHome(tester, at(cairo, 2026, 10, 5, 9, 50));
    expect(find.byTooltip('Diagnostics'), findsOneWidget);
    expect(find.byTooltip('Widget gallery'), findsOneWidget);
    await unmount(tester);
  });

  group('device health chip', () {
    final now = at(cairo, 2026, 10, 5, 9, 50);

    testWidgets('hidden when everything is fine', (tester) async {
      await pumpHome(tester, now, health: HealthHarness());
      expect(find.byKey(const Key('healthChip')), findsNothing);
      await unmount(tester);
    });

    testWidgets('shown for a battery warning on an aggressive OEM', (tester) async {
      final health = HealthHarness(manufacturer: 'Xiaomi Redmi');
      health.platformFake.ignoringBattery = false;
      await pumpHome(tester, now, health: health);
      expect(find.byKey(const Key('healthChip')), findsOneWidget);
      expect(find.text('Check device health'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('hidden for the info-level battery hint and for blocked notifications', (tester) async {
      final health = HealthHarness();
      health.platformFake.ignoringBattery = false;
      health.gateway.enabled = false;
      await pumpHome(tester, now, health: health, gateway: health.gateway);
      expect(find.byKey(const Key('healthChip')), findsNothing);
      await unmount(tester);
    });
  });

  group('reminders paused banner', () {
    final now = at(cairo, 2026, 10, 5, 9, 50);

    testWidgets('appears on the signal and can be dismissed', (tester) async {
      final paused = FakeRemindersPausedSource();
      await pumpHome(tester, now, paused: paused);
      expect(find.byKey(const Key('pausedBanner')), findsNothing);

      paused.emit();
      await tester.pump();
      await tester.pump();
      expect(find.text('Reminders were paused — re-armed now.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Device health'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pausedDismiss')));
      await tester.pump();
      expect(find.byKey(const Key('pausedBanner')), findsNothing);
      await unmount(tester);
    });

    testWidgets('shows for a signal that fired before the page opened, but not one from yesterday', (tester) async {
      await pumpHome(tester, now, paused: FakeRemindersPausedSource()..remindersPausedAt = now);
      expect(find.byKey(const Key('pausedBanner')), findsOneWidget);
      await unmount(tester);

      await pumpHome(
        tester,
        now,
        paused: FakeRemindersPausedSource()..remindersPausedAt = now.subtract(const Duration(days: 1)),
      );
      expect(find.byKey(const Key('pausedBanner')), findsNothing);
      await unmount(tester);
    });
  });
}
