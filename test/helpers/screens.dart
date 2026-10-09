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
import 'package:knight_rise/features/quest_log/presentation/history_cubit.dart';
import 'package:knight_rise/features/quest_log/presentation/history_page.dart';
import 'package:knight_rise/features/quest_log/presentation/quest_log_page.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/reminder_event.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/scheduler/domain/usecases/cycle_usecases.dart';
import 'package:knight_rise/features/settings/presentation/settings_cubit.dart';
import 'package:knight_rise/features/settings/presentation/settings_page.dart';
import 'package:knight_rise/features/settings/presentation/theme_cubit.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:knight_rise/features/shield/presentation/shield_cubit.dart';
import 'package:knight_rise/features/work_hours/domain/usecases/day_override_usecases.dart';
import 'package:knight_rise/l10n/app_locales.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

import 'fakes.dart';
import 'health_fakes.dart';
import 'quest_log_harness.dart';
import 'tz.dart';

/// The four main screens, populated with a realistic mid-day state
/// (Mon 12 Oct 2026, 11:00 Cairo, a 6-day streak, some progress).
enum Screen { today, questLog, history, settings }

/// Pumps [screen] at a phone size (390 × 844) with [textScale], [palette],
/// [locale] and [direction] (a forced direction over the locale's own).
/// Returns a teardown that unmounts it.
Future<void> pumpScreen(
  WidgetTester tester,
  Screen screen, {
  double textScale = 1,
  KnightPalette palette = KnightPalette.midnight,
  TextDirection? direction,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final h = QuestLogHarness(
    now: at(cairo, 2026, 10, 12, 11),
    history: [
      for (var i = 0; i < 30; i++)
        pastDay(
          DateTime.utc(2026, 9, 12).add(Duration(days: i)),
          workDay: ![
            DateTime.friday,
            DateTime.saturday,
          ].contains(DateTime.utc(2026, 9, 12).add(Duration(days: i)).weekday),
          focusMinutes: 25,
        ),
    ],
  );
  await h.events.add(
    ReminderEvent(
      type: RoutineType.hydration,
      outcome: ReminderOutcome.done,
      at: at(cairo, 2026, 10, 12, 9),
      waterMl: 1250,
    ),
  );
  await h.events.add(
    ReminderEvent(type: RoutineType.stretch, outcome: ReminderOutcome.done, at: at(cairo, 2026, 10, 12, 10)),
  );

  final theme = ThemeCubit(h.settings);
  final health = HealthHarness();
  final settingsCubit = SettingsCubit(h.settings, h.schedule);
  addTearDown(theme.close);
  addTearDown(settingsCubit.close);
  addTearDown(health.cubit.close);

  Widget page() => switch (screen) {
    Screen.today => HomePage(
      shieldCubitFactory: () => ShieldCubit(
        StartShield(h.shields, h.schedule, h.overrides, const ReminderPlanner(), h.clock, h.location),
        ExtendShield(h.shields, h.clock),
        EndShield(h.shields, h.clock),
        SetDayOff(h.overrides),
        ExtendWorkDay(h.overrides),
        ClearDayOverride(h.overrides),
        h.clock,
        h.location,
      ),
    ),
    Screen.questLog => QuestLogPage(cubitFactory: h.cubit),
    Screen.history => HistoryPage(cubitFactory: () => HistoryCubit(h.summaries, h.settings, h.clock, h.location)),
    Screen.settings => SettingsPage(cubit: settingsCubit, healthCubit: health.cubit),
  };

  await tester.pumpWidget(
    RepositoryProvider<Clock>.value(
      value: h.clock,
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: theme),
          BlocProvider(
            create: (_) {
              final c = NotificationPermissionCubit(FakeNotificationGateway(), FakeScheduleReconciler());
              unawaited(c.check());
              return c;
            },
          ),
          BlocProvider(
            create: (_) => CycleBloc(
              WatchCycleInputs(h.routines, h.schedule, h.events, h.settings, h.shields, h.overrides),
              const BuildCycleSnapshot(ReminderPlanner()),
              CompleteRoutine(h.events, h.settings, h.clock),
              SnoozeRoutine(h.events, h.clock, cairo),
              h.clock,
              cairo,
            )..add(const CycleStarted()),
          ),
        ],
        child: MaterialApp(
          theme: KnightTheme.build(palette, joinedScript: KnightTheme.isJoinedScript(locale)),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: kSupportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: direction == null ? child! : Directionality(textDirection: direction, child: child!),
          ),
          home: page(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

/// Unmounts the screen and lets timers and animations finish.
Future<void> unmountScreen(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}
