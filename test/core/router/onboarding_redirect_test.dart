import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/router/app_router.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/features/cycle/presentation/bloc/cycle_bloc.dart';
import 'package:knight_rise/features/cycle/presentation/pages/home_page.dart';
import 'package:knight_rise/features/device_health/presentation/device_health_cubit.dart';
import 'package:knight_rise/features/notifications/presentation/notification_permission_cubit.dart';
import 'package:knight_rise/features/onboarding/presentation/onboarding_cubit.dart';
import 'package:knight_rise/features/onboarding/presentation/onboarding_gate.dart';
import 'package:knight_rise/features/onboarding/presentation/onboarding_page.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:knight_rise/features/settings/presentation/settings_cubit.dart';
import 'package:knight_rise/features/settings/presentation/settings_page.dart';
import 'package:knight_rise/features/settings/presentation/theme_cubit.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:knight_rise/features/shield/presentation/shield_cubit.dart';
import 'package:knight_rise/features/work_hours/domain/usecases/day_override_usecases.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';
import '../../helpers/health_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/tz.dart';

void main() {
  test('onboardingRedirect: pure rules', () {
    expect(onboardingRedirect(completed: false, path: '/'), '/onboarding');
    expect(onboardingRedirect(completed: false, path: '/settings'), '/onboarding');
    expect(onboardingRedirect(completed: false, path: '/break'), '/onboarding');
    expect(onboardingRedirect(completed: false, path: '/onboarding'), isNull);
    expect(onboardingRedirect(completed: true, path: '/onboarding'), '/');
    expect(onboardingRedirect(completed: true, path: '/'), isNull);
    expect(onboardingRedirect(completed: true, path: '/settings'), isNull);
  });

  group('router with a gate', () {
    late FakeSettingsRepository settings;
    late FakeRoutineRepository routines;
    late FakeScheduleReconciler reconciler;
    late OnboardingGate gate;
    late HealthHarness health;

    setUp(() {
      settings = FakeSettingsRepository();
      routines = FakeRoutineRepository();
      reconciler = FakeScheduleReconciler();
      final work = FakeWorkScheduleRepository();
      final clock = FixedClock(at(cairo, 2026, 10, 5, 9, 50));
      final shields = FakeShieldRepository();
      final overrides = FakeDayOverrideRepository();
      final location = FakeLocationProvider(cairo);
      // SettingsPage resolves the Device health cubit from DI.
      health = HealthHarness();
      getIt
        ..registerFactory<DeviceHealthCubit>(() => health.cubit)
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
        ..registerFactory<SettingsCubit>(() => SettingsCubit(settings, work))
        ..registerSingleton<Clock>(clock);
      gate = OnboardingGate(settings);
    });

    tearDown(() {
      gate.dispose();
      return getIt.reset();
    });

    Future<GoRouter> pumpAt(WidgetTester tester, String location) async {
      useTallView(tester);
      await gate.load();
      final clock = getIt<Clock>();
      final router = buildRouter(initialLocation: location, gate: gate);
      addTearDown(router.dispose);
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
              BlocProvider(create: (_) => NotificationPermissionCubit(FakeNotificationGateway(), reconciler)),
            ],
            child: MaterialApp.router(
              theme: KnightTheme.build(KnightPalette.midnight),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return router;
    }

    String path(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

    testWidgets('not completed: / goes to onboarding', (tester) async {
      final router = await pumpAt(tester, '/');
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(path(router), '/onboarding');
    });

    testWidgets('not completed: /settings goes to onboarding', (tester) async {
      final router = await pumpAt(tester, '/settings');
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.byType(SettingsPage), findsNothing);
      expect(path(router), '/onboarding');
    });

    testWidgets('completed: /onboarding goes to /', (tester) async {
      await settings.save(settings.current.copyWith(onboardingCompleted: true));
      final router = await pumpAt(tester, '/onboarding');
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
      expect(path(router), '/');
    });

    testWidgets('completed: other routes are untouched', (tester) async {
      await settings.save(settings.current.copyWith(onboardingCompleted: true));
      final router = await pumpAt(tester, '/settings');
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(path(router), '/settings');
    });

    testWidgets('finishing onboarding lands on /', (tester) async {
      final router = await pumpAt(tester, '/');
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('onboarding-primary')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('onboarding-primary')));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(settings.current.onboardingCompleted, isTrue);
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
      expect(path(router), '/');
      expect(reconciler.calls, hasLength(1));
    });
  });
}
