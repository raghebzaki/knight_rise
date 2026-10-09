import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/router/app_router.dart';
import 'package:knight_rise/core/router/break_location.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/features/cycle/presentation/bloc/cycle_bloc.dart';
import 'package:knight_rise/features/cycle/presentation/pages/break_page.dart';
import 'package:knight_rise/features/cycle/presentation/pages/home_page.dart';
import 'package:knight_rise/features/device_health/presentation/device_health_cubit.dart';
import 'package:knight_rise/features/notifications/domain/reminder_action.dart';
import 'package:knight_rise/features/notifications/presentation/notification_permission_cubit.dart';
import 'package:knight_rise/features/onboarding/presentation/onboarding_cubit.dart';
import 'package:knight_rise/features/onboarding/presentation/onboarding_gate.dart';
import 'package:knight_rise/features/onboarding/presentation/onboarding_page.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:knight_rise/features/settings/presentation/theme_cubit.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:knight_rise/features/shield/presentation/shield_cubit.dart';
import 'package:knight_rise/features/splash/presentation/animated_splash.dart';
import 'package:knight_rise/features/work_hours/domain/usecases/day_override_usecases.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';
import '../../helpers/health_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/tz.dart';

/// The splash in the app's real composition: `MaterialApp.router` with the
/// onboarding-gated router, and [SplashOverlay] in its `builder`, the flag
/// held above the router (as in `app.dart`).
void main() {
  late FakeSettingsRepository settings;
  late FakeRoutineRepository routines;
  late OnboardingGate gate;

  setUp(() {
    settings = FakeSettingsRepository();
    routines = FakeRoutineRepository();
    final work = FakeWorkScheduleRepository();
    final clock = FixedClock(at(cairo, 2026, 10, 5, 9, 50));
    final shields = FakeShieldRepository();
    final overrides = FakeDayOverrideRepository();
    final location = FakeLocationProvider(cairo);
    final reconciler = FakeScheduleReconciler();
    getIt
      ..registerFactory<DeviceHealthCubit>(() => HealthHarness().cubit)
      ..registerFactory<OnboardingCubit>(() => OnboardingCubit(routines, work, settings, reconciler))
      ..registerFactory<ShieldCubit>(
        () => ShieldCubit(
          StartShield(shields, work, overrides, const ReminderPlanner(), clock, location),
          ExtendShield(shields, clock),
          EndShield(shields, clock),
          SetDayOff(overrides),
          ExtendWorkDay(overrides),
          ClearDayOverride(overrides),
          clock,
          location,
        ),
      )
      ..registerSingleton<Clock>(clock);
    gate = OnboardingGate(settings);
  });

  tearDown(() {
    gate.dispose();
    return getIt.reset();
  });

  /// A cold start, as in `main.dart`: [notification] is the tap that launched
  /// the app, if any.
  Future<GoRouter> launch(WidgetTester tester, {ReminderAction? notification}) async {
    useTallView(tester);
    await gate.load();
    final clock = getIt<Clock>();
    final router = buildRouter(gate: gate);
    addTearDown(router.dispose);
    var showSplash = SplashOverlay.playsOnLaunch(notification);
    await tester.pumpWidget(
      RepositoryProvider<Clock>.value(
        value: clock,
        child: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => ThemeCubit(settings)),
            BlocProvider(
              create: (_) => CycleBloc(
                WatchCycleInputs(
                  routines,
                  FakeWorkScheduleRepository(),
                  FakeReminderEventRepository(),
                  settings,
                  FakeShieldRepository(),
                  FakeDayOverrideRepository(),
                ),
                const BuildCycleSnapshot(ReminderPlanner()),
                CompleteRoutine(FakeReminderEventRepository(), settings, clock),
                SnoozeRoutine(FakeReminderEventRepository(), clock, cairo),
                clock,
                cairo,
              )..add(const CycleStarted()),
            ),
            BlocProvider(
              create: (_) => NotificationPermissionCubit(FakeNotificationGateway(), FakeScheduleReconciler()),
            ),
          ],
          child: StatefulBuilder(
            builder: (context, setState) => MaterialApp.router(
              theme: KnightTheme.build(KnightPalette.midnight),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
              builder: (context, child) =>
                  SplashOverlay(show: showSplash, onFinished: () => setState(() => showSplash = false), child: child!),
            ),
          ),
        ),
      ),
    );
    if (notification != null) unawaited(router.push(breakLocation(notification.types)));
    await tester.pump();
    return router;
  }

  String path(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

  testWidgets('onboarded user: splash, then Today is revealed (already built underneath)', (tester) async {
    await settings.save(settings.current.copyWith(onboardingCompleted: true));
    final router = await launch(tester);
    expect(find.byType(AnimatedSplash), findsOneWidget);
    expect(find.byType(HomePage), findsOneWidget, reason: 'the first route builds while the splash plays');
    expect(path(router), '/');

    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byType(AnimatedSplash), findsOneWidget, reason: 'still on screen at 1.2 s');

    await tester.pump(const Duration(milliseconds: 800)); // 2.0 s: finished, fading
    await tester.pump(kSplashFadeOut + const Duration(milliseconds: 50));
    expect(find.byType(AnimatedSplash), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('KNIGHT RISE'), findsOneWidget, reason: "Today's app bar, now visible");
    expect(path(router), '/');
  });

  testWidgets('first launch: splash, then the onboarding flow', (tester) async {
    final router = await launch(tester);
    expect(find.byType(AnimatedSplash), findsOneWidget);
    await tester.pump(kSplashDuration + const Duration(milliseconds: 20)); // finished: the fade starts
    await tester.pump(kSplashFadeOut + const Duration(milliseconds: 50));
    expect(find.byType(AnimatedSplash), findsNothing);
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(path(router), '/onboarding');
  });

  test('only a plain launch plays the splash; any notification launch skips it', () {
    expect(SplashOverlay.playsOnLaunch(null), isTrue);
    for (final kind in ReminderActionKind.values) {
      final action = ReminderAction(
        kind: kind,
        types: const {RoutineType.hydration},
        scheduledAt: DateTime.utc(2026, 10, 5, 7),
        notificationId: 42,
      );
      expect(SplashOverlay.playsOnLaunch(action), isFalse, reason: kind.name);
    }
  });

  testWidgets('notification deep link: no splash, the break screen is on screen at once', (tester) async {
    await settings.save(settings.current.copyWith(onboardingCompleted: true));
    await launch(
      tester,
      notification: ReminderAction(
        kind: ReminderActionKind.open,
        types: const {RoutineType.eyeRest},
        scheduledAt: DateTime.utc(2026, 10, 5, 7),
        notificationId: 7,
      ),
    );
    await tester.pump();
    expect(find.byType(AnimatedSplash), findsNothing, reason: 'not even for a frame');
    expect(find.byType(BreakPage), findsOneWidget);

    await tester.pump(kSplashDuration + kSplashFadeOut);
    expect(find.byType(AnimatedSplash), findsNothing, reason: 'and never later');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the splash plays once: later navigation never brings it back', (tester) async {
    await settings.save(settings.current.copyWith(onboardingCompleted: true));
    final router = await launch(tester);
    await tester.pump(kSplashDuration + const Duration(milliseconds: 20));
    await tester.pump(kSplashFadeOut + const Duration(milliseconds: 50));
    expect(find.byType(AnimatedSplash), findsNothing);
    router.go('/onboarding'); // redirected back to '/'
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AnimatedSplash), findsNothing);
    expect(path(router), '/');
  });
}
