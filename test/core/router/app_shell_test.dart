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
import 'package:knight_rise/features/quest_log/presentation/history_cubit.dart';
import 'package:knight_rise/features/quest_log/presentation/history_page.dart';
import 'package:knight_rise/features/quest_log/presentation/quest_log_cubit.dart';
import 'package:knight_rise/features/quest_log/presentation/quest_log_page.dart';
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
import '../../helpers/quest_log_harness.dart';
import '../../helpers/tz.dart';

void main() {
  late QuestLogHarness quest;
  late FakeSettingsRepository settings;
  var questCubits = 0;

  setUp(() {
    quest = QuestLogHarness(now: at(cairo, 2026, 10, 5, 9, 50));
    settings = quest.settings;
    questCubits = 0;
    final clock = quest.clock;
    final work = quest.schedule;
    final location = quest.location;
    getIt
      ..registerFactory<QuestLogCubit>(() {
        questCubits++;
        return quest.cubit();
      })
      ..registerFactory<ShieldCubit>(
        () => ShieldCubit(
          StartShield(quest.shields, work, quest.overrides, const ReminderPlanner(), clock, location),
          ExtendShield(quest.shields, clock),
          EndShield(quest.shields, clock),
          SetDayOff(quest.overrides),
          ExtendWorkDay(quest.overrides),
          ClearDayOverride(quest.overrides),
          clock,
          location,
        ),
      )
      ..registerFactory<HistoryCubit>(() => HistoryCubit(quest.summaries, settings, clock, location))
      ..registerFactory<SettingsCubit>(() => SettingsCubit(settings, work))
      ..registerFactory<DeviceHealthCubit>(() => HealthHarness().cubit);
  });

  tearDown(getIt.reset);

  Future<GoRouter> pumpAt(WidgetTester tester, String location) async {
    useTallView(tester);
    final router = buildRouter(initialLocation: location);
    addTearDown(router.dispose);
    final clock = quest.clock;
    await tester.pumpWidget(
      RepositoryProvider<Clock>.value(
        value: clock,
        child: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => ThemeCubit(settings)),
            BlocProvider(
              create: (_) => CycleBloc(
                WatchCycleInputs(
                  quest.routines,
                  quest.schedule,
                  quest.events,
                  settings,
                  quest.shields,
                  quest.overrides,
                ),
                const BuildCycleSnapshot(ReminderPlanner()),
                CompleteRoutine(quest.events, settings, clock),
                SnoozeRoutine(quest.events, clock, cairo),
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
    return router;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  String path(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;
  Finder tab(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
  int selectedTab(WidgetTester tester) => tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  testWidgets('/ shows Today with the bottom navigation; the Quest Log is built lazily', (tester) async {
    final router = await pumpAt(tester, '/');
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(selectedTab(tester), 0);
    expect(questCubits, 0);
    expect(path(router), '/');
    await unmount(tester);
  });

  testWidgets('tabs switch between / and /quest and keep their state', (tester) async {
    final router = await pumpAt(tester, '/');
    await tester.tap(tab('Quest Log'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(path(router), '/quest');
    expect(find.byType(QuestLogPage), findsOneWidget);
    expect(selectedTab(tester), 1);

    await tester.tap(tab('Today'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(path(router), '/');
    expect(find.byType(HomePage), findsOneWidget);

    await tester.tap(tab('Quest Log'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(questCubits, 1); // the Quest Log page (and its cubit) survived the switch
    await unmount(tester);
  });

  testWidgets('/quest opens the Quest Log tab directly', (tester) async {
    final router = await pumpAt(tester, '/quest');
    expect(find.byType(QuestLogPage), findsOneWidget);
    expect(selectedTab(tester), 1);
    expect(path(router), '/quest');
    await unmount(tester);
  });

  testWidgets('settings open full screen above the tabs, and back returns to them', (tester) async {
    await pumpAt(tester, '/');
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a water log on the Quest Log shows up on Today', (tester) async {
    await pumpAt(tester, '/quest');
    await tester.tap(find.byKey(const Key('water-500')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(tab('Today'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('500 ml today'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('/history opens the History tab; the tab bar reaches it from Today', (tester) async {
    var router = await pumpAt(tester, '/history');
    expect(find.byType(HistoryPage), findsOneWidget);
    expect(selectedTab(tester), 2);
    await unmount(tester);

    router = await pumpAt(tester, '/');
    await tester.tap(tab('History'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(path(router), '/history');
    expect(find.byType(HistoryPage), findsOneWidget);
    await unmount(tester);
  });
}
