import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/router/app_router.dart';
import 'package:knight_rise/core/shortcuts/app_shortcuts.dart';
import 'package:knight_rise/core/shortcuts/shortcuts_dialog.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/features/cycle/presentation/bloc/cycle_bloc.dart';
import 'package:knight_rise/features/notifications/presentation/notification_permission_cubit.dart';
import 'package:knight_rise/features/quest_log/presentation/quest_log_cubit.dart';
import 'package:knight_rise/features/scheduler/domain/services/reminder_planner.dart';
import 'package:knight_rise/features/settings/presentation/theme_cubit.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:knight_rise/features/shield/presentation/shield_cubit.dart';
import 'package:knight_rise/features/work_hours/domain/usecases/day_override_usecases.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';
import '../../helpers/quest_log_harness.dart';
import '../../helpers/spy_cycle_bloc.dart';
import '../../helpers/tz.dart';

void main() {
  late QuestLogHarness quest;
  late SpyCycleBloc bloc;
  late GoRouter router;

  setUp(() {
    quest = QuestLogHarness(now: at(cairo, 2026, 10, 5, 9, 1));
    final clock = quest.clock;
    getIt
      ..registerFactory<QuestLogCubit>(quest.cubit)
      ..registerFactory<ShieldCubit>(
        () => ShieldCubit(
          StartShield(quest.shields, quest.schedule, quest.overrides, const ReminderPlanner(), clock, quest.location),
          ExtendShield(quest.shields, clock),
          EndShield(quest.shields, clock),
          SetDayOff(quest.overrides),
          ExtendWorkDay(quest.overrides),
          ClearDayOverride(quest.overrides),
          clock,
          quest.location,
        ),
      );
  });

  tearDown(getIt.reset);

  Future<void> pumpToday(WidgetTester tester, {Size size = const Size(1300, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bloc = SpyCycleBloc(quest);
    router = buildRouter();
    await tester.pumpWidget(
      RepositoryProvider<Clock>.value(
        value: quest.clock,
        child: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => ThemeCubit(quest.settings)),
            BlocProvider<CycleBloc>.value(value: bloc..add(const CycleStarted())),
            BlocProvider(
              create: (_) => NotificationPermissionCubit(FakeNotificationGateway(), FakeScheduleReconciler()),
            ),
          ],
          child: MaterialApp.router(
            theme: KnightTheme.build(KnightPalette.midnight),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
            builder: (context, child) => AppShortcuts(router: router, nativeMenu: false, child: child!),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tab(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }

  /// Closes the app and lets timers finish, as the invariants require.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    unawaited(bloc.close()); // microtasks run in the pump below
    router.dispose();
    await tester.pump(const Duration(seconds: 1));
  }

  bool inRail(BuildContext? c) => c?.findAncestorWidgetOfExactType<NavigationRail>() != null;

  String path() => router.routerDelegate.currentConfiguration.last.matchedLocation;

  /// Focuses the rail destination labelled [label], as a click or a Shift+Tab out of the page would.
  Future<void> focusRail(WidgetTester tester, String label) async {
    final text = find.descendant(of: find.byType(NavigationRail), matching: find.text(label)).first;
    Focus.of(tester.element(text)).requestFocus();
    await tester.pump();
  }

  testWidgets('Tab walks the four rail destinations, then moves into the content', (tester) async {
    await pumpToday(tester);
    expect(find.byType(NavigationRail), findsOneWidget);
    // The page owns the initial focus; from the first destination Tab visits the rest of the rail in order.
    await focusRail(tester, 'Today');
    final railFocus = [FocusManager.instance.primaryFocus!];
    for (var i = 1; i < 4; i++) {
      await tab(tester);
      railFocus.add(FocusManager.instance.primaryFocus!);
    }
    expect(railFocus.every((n) => inRail(n.context)), isTrue);
    expect(railFocus.toSet(), hasLength(4));
    expect([for (final n in railFocus) n.rect.top], orderedEquals([...railFocus.map((n) => n.rect.top)]..sort()));
    // Tab from the last destination enters the page.
    await tab(tester);
    final inContent = FocusManager.instance.primaryFocus!;
    expect(inRail(inContent.context), isFalse);
    expect(inContent.context!.findAncestorWidgetOfExactType<Scaffold>(), isNotNull);
    // Shift+Tab goes back to the last destination.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, railFocus.last);
    await finish(tester);
  });

  testWidgets('every Today control is reachable by Tab (no focus trap)', (tester) async {
    await pumpToday(tester);
    final seen = <FocusNode>{};
    for (var i = 0; i < 60; i++) {
      await tab(tester);
      seen.add(FocusManager.instance.primaryFocus!);
    }
    // The 4 rail destinations plus the page's buttons: past the content, focus wraps around instead of getting stuck.
    expect(seen.length, greaterThan(10));
    expect(seen.length, lessThan(60));
    await finish(tester);
  });

  testWidgets('Enter on a focused rail destination switches branch', (tester) async {
    await pumpToday(tester);
    await focusRail(tester, 'Quest Log');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(path(), '/quest');
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex, 1);
    await finish(tester);
  });

  testWidgets('Space on a focused Done button completes that routine', (tester) async {
    await pumpToday(tester);
    final done = find.widgetWithText(FilledButton, 'Done').first;
    Focus.of(tester.element(find.descendant(of: done, matching: find.byType(Text)).first)).requestFocus();
    await tester.pump();
    bloc.reset();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(bloc.completed, hasLength(1));
    await finish(tester);
  });

  testWidgets('Enter on a focused Snooze button snoozes that routine', (tester) async {
    await pumpToday(tester);
    final snooze = find.widgetWithText(TextButton, 'Snooze 10m').first;
    expect(tester.widget<TextButton>(snooze).onPressed, isNotNull);
    Focus.of(tester.element(find.descendant(of: snooze, matching: find.byType(Text)).first)).requestFocus();
    await tester.pump();
    bloc.reset();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(bloc.snoozed, hasLength(1));
    await finish(tester);
  });

  testWidgets('a closed dialog returns focus to the control that had it', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      shortcutsDialogOpen.value = false;
      await pumpToday(tester);
      await focusRail(tester, 'History');
      final before = FocusManager.instance.primaryFocus;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ShortcutsDialog), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, isNot(before));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ShortcutsDialog), findsNothing);
      expect(FocusManager.instance.primaryFocus, before);
      await finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('RTL: the rail is on the right and Tab walks it before the page', (tester) async {
    tester.view.physicalSize = const Size(1300, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bloc = SpyCycleBloc(quest);
    router = buildRouter();
    await tester.pumpWidget(
      RepositoryProvider<Clock>.value(
        value: quest.clock,
        child: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => ThemeCubit(quest.settings)),
            BlocProvider<CycleBloc>.value(value: bloc..add(const CycleStarted())),
            BlocProvider(
              create: (_) => NotificationPermissionCubit(FakeNotificationGateway(), FakeScheduleReconciler()),
            ),
          ],
          child: MaterialApp.router(
            theme: KnightTheme.build(KnightPalette.midnight),
            locale: const Locale('ar'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(find.byType(NavigationRail)).dx, greaterThan(650));
    await focusRail(tester, 'اليوم');
    final first = FocusManager.instance.primaryFocus!;
    expect(inRail(first.context), isTrue);
    for (var i = 0; i < 3; i++) {
      await tab(tester);
      expect(inRail(FocusManager.instance.primaryFocus!.context), isTrue);
    }
    await tab(tester);
    expect(inRail(FocusManager.instance.primaryFocus!.context), isFalse);
    await finish(tester);
  });
}
