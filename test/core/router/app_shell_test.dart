import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/platform/system_settings_launcher.dart';
import 'package:knight_rise/core/router/app_router.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/features/cycle/presentation/bloc/cycle_bloc.dart';
import 'package:knight_rise/features/cycle/presentation/pages/home_page.dart';
import 'package:knight_rise/features/device_health/presentation/device_health_cubit.dart';
import 'package:knight_rise/features/notifications/presentation/notification_permission_cubit.dart';
import 'package:knight_rise/features/quest_log/domain/services/day_summarizer.dart';
import 'package:knight_rise/features/quest_log/domain/services/streak_calculator.dart';
import 'package:knight_rise/features/quest_log/presentation/history_cubit.dart';
import 'package:knight_rise/features/quest_log/presentation/history_page.dart';
import 'package:knight_rise/features/quest_log/presentation/quest_log_cubit.dart';
import 'package:knight_rise/features/quest_log/presentation/quest_log_page.dart';
import 'package:knight_rise/features/quest_log/presentation/rank_up_cubit.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/routines/presentation/routine_editor_cubit.dart';
import 'package:knight_rise/features/routines/presentation/routine_editor_page.dart';
import 'package:knight_rise/features/routines/presentation/routines_cubit.dart';
import 'package:knight_rise/features/routines/presentation/routines_page.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:knight_rise/features/settings/presentation/settings_cubit.dart';
import 'package:knight_rise/features/settings/presentation/settings_page.dart';
import 'package:knight_rise/features/settings/presentation/theme_cubit.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:knight_rise/features/shield/presentation/shield_cubit.dart';
import 'package:knight_rise/features/work_hours/domain/usecases/day_override_usecases.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

import '../../helpers/fake_launcher.dart';
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
      ..registerFactory<RankUpCubit>(
        () => RankUpCubit(
          WatchCycleInputs(quest.routines, work, quest.events, settings, quest.shields, quest.overrides),
          quest.summaries,
          const DaySummarizer(),
          const StreakCalculator(),
          settings,
          clock,
          location,
        ),
      )
      ..registerFactory<HistoryCubit>(() => HistoryCubit(quest.summaries, settings, clock, location))
      ..registerFactory<SettingsCubit>(() => SettingsCubit(settings, work))
      ..registerFactory<DeviceHealthCubit>(() => HealthHarness().cubit)
      ..registerSingleton<SystemSettingsLauncher>(FakeSystemSettingsLauncher())
      ..registerFactory<RoutinesCubit>(() => RoutinesCubit(quest.routines))
      ..registerFactoryParam<RoutineEditorCubit, RoutineType, void>(
        (t, _) => RoutineEditorCubit(quest.routines, settings, t),
      );
  });

  tearDown(getIt.reset);

  Future<GoRouter> pumpAt(WidgetTester tester, String location, {Size? size, Locale? locale}) async {
    if (size == null) {
      useTallView(tester);
    } else {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
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
            locale: locale,
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

  testWidgets('the Home gear switches to the Settings branch, with the bar still showing', (tester) async {
    final router = await pumpAt(tester, '/');
    await tester.tap(find.byTooltip('Settings').first);
    await tester.pumpAndSettle();
    expect(path(router), '/settings');
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(selectedTab(tester), 3);
    await unmount(tester);
  });

  testWidgets('/settings/routines/eyeRest deep-links into the Settings branch', (tester) async {
    await pumpAt(tester, '/settings/routines/eyeRest');
    expect(find.byType(RoutineEditorPage), findsOneWidget);
    expect(selectedTab(tester), 3);
    await unmount(tester);
  });

  group('adaptive navigation', () {
    const compact = Size(400, 800);
    const medium = Size(700, 900);
    const expanded = Size(1000, 800);
    const large = Size(1300, 900);

    NavigationRail rail(WidgetTester tester) => tester.widget<NavigationRail>(find.byType(NavigationRail));

    testWidgets('compact: bottom bar with four destinations, no rail', (tester) async {
      await pumpAt(tester, '/', size: compact);
      expect(find.byType(NavigationRail), findsNothing);
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations, hasLength(4));
      await unmount(tester);
    });

    testWidgets('medium: rail without labels, not extended', (tester) async {
      await pumpAt(tester, '/', size: medium);
      expect(find.byType(NavigationBar), findsNothing);
      expect(rail(tester).labelType, NavigationRailLabelType.none);
      expect(rail(tester).extended, isFalse);
      expect(rail(tester).destinations, hasLength(4));
      await unmount(tester);
    });

    testWidgets('expanded: rail with labels', (tester) async {
      await pumpAt(tester, '/', size: expanded);
      expect(rail(tester).labelType, NavigationRailLabelType.all);
      expect(rail(tester).extended, isFalse);
      await unmount(tester);
    });

    testWidgets('large: extended sidebar with the app title', (tester) async {
      await pumpAt(tester, '/', size: large);
      expect(rail(tester).extended, isTrue);
      expect(rail(tester).minExtendedWidth, 256);
      expect(find.text('Knight Rise'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('every destination switches branch; reselecting resets it', (tester) async {
      final router = await pumpAt(tester, '/', size: large);
      Future<void> go(String label) async {
        await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text(label)));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }

      await go('Quest Log');
      expect(path(router), '/quest');
      expect(find.byType(QuestLogPage), findsOneWidget);
      await go('History');
      expect(path(router), '/history');
      expect(find.byType(HistoryPage), findsOneWidget);
      await go('Settings');
      expect(path(router), '/settings');
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(rail(tester).selectedIndex, 3);
      await go('Today');
      expect(path(router), '/');
      expect(find.byType(HomePage), findsOneWidget);

      // Settings deep page, then reselect Settings: back to its first page.
      router.go('/settings/routines');
      await tester.pumpAndSettle();
      expect(find.byType(RoutinesPage), findsOneWidget);
      await go('Settings');
      expect(path(router), '/settings');
      expect(find.byType(SettingsPage), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('resizing compact to large keeps the branch and its state', (tester) async {
      final router = await pumpAt(tester, '/quest', size: compact);
      expect(selectedTab(tester), 1);
      tester.view.physicalSize = large;
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(rail(tester).selectedIndex, 1);
      expect(path(router), '/quest');
      expect(find.byType(QuestLogPage), findsOneWidget);
      expect(questCubits, 1);
      await unmount(tester);
    });

    for (final (locale, name) in [(const Locale('ar'), 'Arabic'), (const Locale('en'), 'English')]) {
      final rtl = locale.languageCode == 'ar';
      for (final size in [medium, large]) {
        testWidgets('$name at ${size.width.toInt()}: rail on the ${rtl ? 'right' : 'left'} edge', (tester) async {
          await pumpAt(tester, '/', size: size, locale: locale);
          final left = tester.getTopLeft(find.byType(NavigationRail)).dx;
          if (rtl) {
            expect(left, greaterThan(size.width / 2));
          } else {
            expect(left, 0);
          }
          await unmount(tester);
        });
      }

      testWidgets('$name compact bar: Today is on the ${rtl ? 'right' : 'left'}', (tester) async {
        await pumpAt(tester, '/', size: compact, locale: locale);
        final today = tester.getCenter(
          find.descendant(of: find.byType(NavigationBar), matching: find.byIcon(Icons.today)),
        );
        final settingsIcon = tester.getCenter(
          find.descendant(of: find.byType(NavigationBar), matching: find.byIcon(Icons.settings_outlined)),
        );
        expect(today.dx < settingsIcon.dx, !rtl);
        await unmount(tester);
      });
    }
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

  testWidgets('a pending rank-up is celebrated on Today, once', (tester) async {
    // Mon 5 Oct: Sun 4 .. Thu 1 qualified around a weekend → Squire, never shown.
    for (final n in [1, 4]) {
      await quest.summaries.upsert(pastDay(DateTime.utc(2026, 10, n)));
    }
    await quest.summaries.upsert(pastDay(DateTime.utc(2026, 9, 30)));
    for (final n in [2, 3]) {
      await quest.summaries.upsert(pastDay(DateTime.utc(2026, 10, n), workDay: false));
    }
    await pumpAt(tester, '/');
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('RANK UP!'), findsOneWidget);
    expect(find.text('You rose to Squire with a 3-day streak.'), findsOneWidget);
    expect(settings.current.rankCelebratedOn, DateTime.utc(2026, 10, 5));

    await tester.tap(find.text('Onward'));
    await tester.pumpAndSettle();
    expect(find.text('RANK UP!'), findsNothing);

    // Switching tabs does not show it again.
    await tester.tap(tab('Quest Log'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('RANK UP!'), findsNothing);
    await unmount(tester);
  });
}
