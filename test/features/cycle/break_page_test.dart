import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/feedback/haptics.dart';
import 'package:knight_rise/core/router/app_router.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/features/cycle/presentation/bloc/cycle_bloc.dart';
import 'package:knight_rise/features/notifications/presentation/notification_permission_cubit.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:knight_rise/features/settings/presentation/theme_cubit.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:knight_rise/features/shield/presentation/shield_cubit.dart';
import 'package:knight_rise/features/work_hours/domain/usecases/day_override_usecases.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';
import '../../helpers/tz.dart';

void main() {
  late FakeReminderEventRepository events;
  late GoRouter router;
  late List<String> haptics;

  Future<void> pumpApp(WidgetTester tester) async {
    events = FakeReminderEventRepository();
    final settings = FakeSettingsRepository();
    final clock = FixedClock(at(cairo, 2026, 10, 5, 9, 50));
    haptics = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // The real router builds HomePage, which resolves its ShieldCubit from DI.
    final shields = FakeShieldRepository();
    final overrides = FakeDayOverrideRepository();
    final location = FakeLocationProvider(cairo);
    getIt.registerFactory<ShieldCubit>(
      () => ShieldCubit(
        StartShield(shields, FakeWorkScheduleRepository(), overrides, const ReminderPlanner(), clock, location),
        ExtendShield(shields, clock),
        EndShield(shields, clock),
        SetDayOff(overrides),
        ExtendWorkDay(overrides),
        ClearDayOverride(overrides),
        clock,
        location,
      ),
    );
    addTearDown(() => getIt.unregister<ShieldCubit>());

    router = buildRouter();
    // The real service, so taps go through the setting to the platform channel.
    final hapticsService = Haptics(settings);
    addTearDown(hapticsService.dispose);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<Clock>.value(value: clock),
          RepositoryProvider<Haptics>.value(value: hapticsService),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => ThemeCubit(settings)),
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
            BlocProvider(
              create: (_) => NotificationPermissionCubit(FakeNotificationGateway(), FakeScheduleReconciler()),
            ),
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
  }

  Future<void> open(WidgetTester tester, String location) async {
    unawaited(router.push<void>(location));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Finder filledButton(String label) => find.widgetWithText(FilledButton, label);
  Finder outlinedButton(String label) => find.widgetWithText(OutlinedButton, label);

  testWidgets('eye rest: countdown completes after 20 s, haptic fires, Done dispatches and closes', (tester) async {
    await pumpApp(tester);
    await open(tester, '/break?types=eyeRest');

    expect(find.text('Look 20 ft away'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(filledButton('Start'), findsOneWidget);
    expect(outlinedButton('Done'), findsOneWidget);

    await tester.tap(filledButton('Start'));
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('15'), findsOneWidget);
    expect(filledButton('Start'), findsNothing);
    expect(outlinedButton('Done'), findsOneWidget);
    expect(haptics, isEmpty);

    await tester.pump(const Duration(seconds: 14));
    expect(find.text('1'), findsOneWidget);
    expect(haptics, isEmpty);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0'), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    expect(filledButton('Done'), findsOneWidget, reason: 'Done becomes primary at 0');
    expect(outlinedButton('Done'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('0'), findsOneWidget, reason: 'countdown stops at 0');
    expect(haptics, hasLength(1));

    await tester.tap(filledButton('Done'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(haptics.last, 'HapticFeedbackType.mediumImpact', reason: 'Done plays the success haptic');
    expect(events.all, hasLength(1));
    expect(events.all.single.type, RoutineType.eyeRest);
    expect(events.all.single.outcome, ReminderOutcome.done);
    expect(find.text('Look 20 ft away'), findsNothing);
    expect(find.text('KNIGHT RISE'), findsOneWidget);
    expect(find.text('Quest updated'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('eye rest: Done is allowed before the countdown starts', (tester) async {
    await pumpApp(tester);
    await open(tester, '/break?types=eyeRest');

    await tester.tap(outlinedButton('Done'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(events.all.map((e) => e.type), [RoutineType.eyeRest]);
    expect(find.text('Quest updated'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('stretch: lists four steps and Done completes', (tester) async {
    await pumpApp(tester);
    await open(tester, '/break?types=stretch');

    expect(find.byType(CheckboxListTile), findsNWidgets(4));
    await tester.tap(find.text('Neck rolls'));
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile).first).value, isTrue);

    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(events.all.map((e) => e.type), [RoutineType.stretch]);
    expect(events.all.single.waterMl, isNull);
    await unmount(tester);
  });

  testWidgets('hydration: 250 ml is preselected', (tester) async {
    await pumpApp(tester);
    await open(tester, '/break?types=hydration');

    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '250 ml')).selected, isTrue);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '150 ml')).selected, isFalse);

    await tester.tap(filledButton('Log water'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(events.all.single.waterMl, 250);
    await unmount(tester);
  });

  testWidgets('hydration: choosing 500 ml logs 500', (tester) async {
    await pumpApp(tester);
    await open(tester, '/break?types=hydration');

    await tester.tap(find.widgetWithText(ChoiceChip, '500 ml'));
    await tester.pump();
    await tester.tap(filledButton('Log water'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(events.all, hasLength(1));
    expect(events.all.single.type, RoutineType.hydration);
    expect(events.all.single.outcome, ReminderOutcome.done);
    expect(events.all.single.waterMl, 500);
    expect(find.text('500 ml today'), findsOneWidget);
    expect(find.text('Quest updated'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('several types: one page each in routine order; closes after the last', (tester) async {
    await pumpApp(tester);
    await open(tester, '/break?types=eyeRest,hydration');

    // Hydration comes first regardless of the order in the URL.
    expect(find.text('Log water'), findsOneWidget);
    expect(find.bySemanticsLabel('Step 1 of 2'), findsOneWidget);

    await tester.tap(filledButton('Log water'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(events.all.map((e) => e.type), [RoutineType.hydration]);
    expect(find.text('Look 20 ft away'), findsOneWidget);
    expect(find.text('Quest updated'), findsNothing, reason: 'still one routine to go');

    await tester.tap(outlinedButton('Done'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(events.all.map((e) => e.type), [RoutineType.hydration, RoutineType.eyeRest]);
    expect(find.text('Look 20 ft away'), findsNothing);
    expect(find.text('Quest updated'), findsOneWidget);
    await unmount(tester);
  });

  for (final location in ['/break', '/break?types=', '/break?types=nope,,', '/break?types=Hydration']) {
    testWidgets('invalid types ($location) redirect to the dashboard', (tester) async {
      await pumpApp(tester);
      router.go(location);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('KNIGHT RISE'), findsOneWidget);
      expect(find.text('Break time'.toUpperCase()), findsNothing);
      expect(events.all, isEmpty);
      await unmount(tester);
    });
  }

  testWidgets('deep link without history: Done goes home', (tester) async {
    await pumpApp(tester);
    router.go('/break?types=stretch'); // replaces the stack, nothing to pop
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('QUICK STRETCH'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('KNIGHT RISE'), findsOneWidget);
    expect(find.text('Quest updated'), findsOneWidget);
    await unmount(tester);
  });
}
