import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:knight_rise/core/clock/clock.dart';
import 'package:knight_rise/core/router/app_shell.dart';
import 'package:knight_rise/core/router/break_location.dart';
import 'package:knight_rise/core/shortcuts/app_bindings.dart';
import 'package:knight_rise/core/shortcuts/app_intents.dart';
import 'package:knight_rise/core/shortcuts/app_shortcuts.dart';
import 'package:knight_rise/core/shortcuts/shortcuts_dialog.dart';
import 'package:knight_rise/core/theme/knight_palette.dart';
import 'package:knight_rise/core/theme/knight_theme.dart';
import 'package:knight_rise/features/cycle/presentation/bloc/cycle_bloc.dart';
import 'package:knight_rise/features/cycle/presentation/pages/break_page.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/cycle_snapshot.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:knight_rise/features/splash/presentation/animated_splash.dart';
import 'package:knight_rise/l10n/app_locales.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';
import 'package:knight_rise/l10n/generated/app_localizations_ar.dart';
import 'package:knight_rise/l10n/generated/app_localizations_en.dart';

import '../../helpers/fakes.dart';
import '../../helpers/quest_log_harness.dart';
import '../../helpers/spy_cycle_bloc.dart';
import '../../helpers/tz.dart';

/// Placeholder branch page with a text field, to check shortcuts while typing.
class _Page extends StatelessWidget {
  const _Page(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text('page-$name'),
        const TextField(key: Key('field')),
      ],
    ),
  );
}

GoRouter _router(String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(path: '/onboarding', builder: (_, _) => const _Page('onboarding')),
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => AppShell(shell: shell),
      branches: [
        for (final p in ['/', '/quest', '/history', '/settings'])
          StatefulShellBranch(
            routes: [GoRoute(path: p, builder: (_, _) => _Page(p))],
          ),
      ],
    ),
    GoRoute(
      path: '/break',
      builder: (_, state) => BreakPage(types: parseBreakTypes(state.uri.queryParameters['types'])),
    ),
  ],
);

/// Fake native menu: records what the app hands to the platform instead of calling the macOS channel.
class _FakeMenuDelegate implements PlatformMenuDelegate {
  List<PlatformMenuItem> menus = const [];
  int sets = 0;

  @override
  void setMenus(List<PlatformMenuItem> topLevelMenus) {
    menus = topLevelMenus;
    sets++;
  }

  @override
  void clearMenus() => menus = const [];

  @override
  bool debugLockDelegate(BuildContext context) => true;

  @override
  bool debugUnlockDelegate(BuildContext context) => true;
}

/// Every leaf item (selectable or provided) in [items], depth first.
Iterable<PlatformMenuItem> _flatten(Iterable<PlatformMenuItem> items) sync* {
  for (final item in items) {
    if (item is PlatformMenu) {
      yield* _flatten(item.menus);
    } else if (item is PlatformMenuItemGroup) {
      yield* _flatten(item.members);
    } else {
      yield item;
    }
  }
}

/// Whether [item]'s shortcut is [binding]'s macOS key combination.
bool _carries(PlatformMenuItem item, AppBinding binding) {
  final a = item.shortcut;
  final b = binding.activator(TargetPlatform.macOS);
  return a is SingleActivator &&
      a.trigger == b.trigger &&
      a.meta == b.meta &&
      a.control == b.control &&
      a.shift == b.shift &&
      a.alt == b.alt;
}

void main() {
  late QuestLogHarness h;
  late SpyCycleBloc bloc;
  late FakePlatformShell shell;
  late GoRouter router;
  late List<bool> shieldToggles;
  final closers = <Future<void> Function()>[];

  setUp(() {
    shortcutsDialogOpen.value = false;
    h = QuestLogHarness(now: at(cairo, 2026, 10, 5, 9, 50));
    shell = FakePlatformShell();
    shieldToggles = [];
  });

  /// Pumps the shell app at [platform], optionally at [initial] and with the native menu forced to [native].
  Future<void> pumpApp(
    WidgetTester tester, {
    String initial = '/',
    bool? native = false,
    Locale? locale,
    Size size = const Size(1300, 900),
    List<Routine>? routines,
    Widget Function(Widget child)? wrap,
  }) async {
    if (routines != null) {
      for (final r in routines) {
        await h.routines.save(r);
      }
    }
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bloc = SpyCycleBloc(h)..add(const CycleStarted());
    closers.add(bloc.close);
    router = _router(initial);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      RepositoryProvider<Clock>.value(
        value: h.clock,
        child: BlocProvider<CycleBloc>.value(
          value: bloc,
          child: MaterialApp.router(
            theme: KnightTheme.build(KnightPalette.midnight),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: kSupportedLocales,
            routerConfig: router,
            builder: (context, child) => AppShortcuts(
              router: router,
              platformShell: shell,
              nativeMenu: native,
              toggleFocusShield: ({required active}) async => shieldToggles.add(active),
              child: wrap == null ? child! : wrap(child!),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  String path() => router.routerDelegate.currentConfiguration.last.matchedLocation;

  /// Holds the platform modifier (and Shift) while pressing [key].
  Future<void> chord(WidgetTester tester, LogicalKeyboardKey key, {bool shift = false, bool? command}) async {
    final useCommand = command ?? usesCommandKey(defaultTargetPlatform);
    final mod = useCommand ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(mod);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(mod);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  /// A widget test on [platform] that always resets the override and unmounts first.
  void platformTest(String name, TargetPlatform platform, Future<void> Function(WidgetTester tester) body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        // Closing needs microtasks to run: pump below instead of awaiting inside the fake-async zone.
        closers.map((close) => close()).forEach(unawaited);
        closers.clear();
        await tester.pump(const Duration(seconds: 1));
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  group('target rule', () {
    CycleSnapshot snapshot({
      required Map<RoutineType, RoutineStatus> status,
      Set<RoutineType> next = const {},
      bool onDuty = true,
      Set<RoutineType> cannotSnooze = const {},
      Set<RoutineType> disabled = const {},
    }) {
      final t = DateTime(2026, 10, 5, 10);
      return CycleSnapshot(
        computedAt: t,
        routines: [
          for (final r in Routine.defaults)
            RoutineView(
              routine: r.copyWith(enabled: !disabled.contains(r.type)),
              status: status[r.type] ?? StatusUpcoming(t),
              doneToday: 0,
              canSnooze: !cannotSnooze.contains(r.type),
              progress: 0,
            ),
        ],
        onDuty: onDuty,
        waterMlToday: 0,
        waterTargetMl: 2000,
        nextChangeAt: t,
        nextUp: next.isEmpty ? null : PlannedReminder(fireAt: t, types: next),
      );
    }

    test('due routines win over the next-up reminder', () {
      final s = snapshot(
        status: {RoutineType.stretch: StatusDue(DateTime(2026, 10, 5, 9, 40))},
        next: {RoutineType.eyeRest, RoutineType.hydration},
      );
      expect(shortcutTargets(s), [RoutineType.stretch]);
    });

    test('without anything due, the next-up routines are the target', () {
      final s = snapshot(status: {}, next: {RoutineType.eyeRest, RoutineType.hydration});
      expect(shortcutTargets(s), unorderedEquals([RoutineType.eyeRest, RoutineType.hydration]));
    });

    test('nothing off duty, with no next-up, without a snapshot, or for disabled routines', () {
      expect(shortcutTargets(snapshot(status: {}, next: {RoutineType.eyeRest}, onDuty: false)), isEmpty);
      expect(shortcutTargets(snapshot(status: {})), isEmpty);
      expect(shortcutTargets(null), isEmpty);
      expect(
        shortcutTargets(snapshot(status: {}, next: {RoutineType.eyeRest}, disabled: {RoutineType.eyeRest})),
        isEmpty,
      );
    });

    test('snooze skips routines that cannot be snoozed or are shielded', () {
      final s = snapshot(
        status: {RoutineType.hydration: StatusShielded(DateTime(2026, 10, 5, 11))},
        next: {RoutineType.eyeRest, RoutineType.hydration, RoutineType.stretch},
        cannotSnooze: {RoutineType.stretch},
      );
      expect(snoozeTargets(s), [RoutineType.eyeRest]);
    });
  });

  group('table', () {
    test('every binding has a distinct key combination per platform', () {
      for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
        final map = AppBindings.shortcuts(platform);
        expect(map.length, AppBindings.all.length);
      }
    });

    test('key caps use glyphs on macOS and words elsewhere', () {
      expect(AppBindings.snooze.caps(TargetPlatform.macOS), ['⌘', '⇧', 'S']);
      expect(AppBindings.snooze.caps(TargetPlatform.windows), ['Ctrl', 'Shift', 'S']);
      expect(AppBindings.done.caps(TargetPlatform.macOS), ['⌘', '↩']);
      expect(AppBindings.done.caps(TargetPlatform.windows), ['Ctrl', 'Enter']);
      expect(AppBindings.showShortcuts.caps(TargetPlatform.linux), ['Ctrl', '/']);
      expect(AppBindings.openSettings.caps(TargetPlatform.iOS), ['⌘', ',']);
    });
  });

  group('bindings on Windows', () {
    platformTest('Ctrl+1..4 switch branches, keeping each branch state', TargetPlatform.windows, (tester) async {
      await pumpApp(tester);
      await chord(tester, LogicalKeyboardKey.digit2);
      expect(path(), '/quest');
      await chord(tester, LogicalKeyboardKey.digit3);
      expect(path(), '/history');
      await chord(tester, LogicalKeyboardKey.digit4);
      expect(path(), '/settings');
      await chord(tester, LogicalKeyboardKey.digit1);
      expect(path(), '/');
      expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex, 0);
    });

    platformTest('Ctrl+, opens Settings', TargetPlatform.windows, (tester) async {
      await pumpApp(tester);
      await chord(tester, LogicalKeyboardKey.comma);
      expect(path(), '/settings');
    });

    platformTest('the Meta key does nothing on Windows', TargetPlatform.windows, (tester) async {
      await pumpApp(tester);
      await chord(tester, LogicalKeyboardKey.digit2, command: true);
      expect(path(), '/');
    });

    platformTest(
      'navigation also works while a text field has focus, and typing is untouched',
      TargetPlatform.windows,
      (tester) async {
        await pumpApp(tester);
        await tester.tap(find.byKey(const Key('field')));
        await tester.pump();
        await tester.enterText(find.byKey(const Key('field')), 'abc');
        expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
        await chord(tester, LogicalKeyboardKey.digit2);
        expect(path(), '/quest');
      },
    );

    platformTest('Ctrl+Enter completes the next-up reminder routines', TargetPlatform.windows, (tester) async {
      h = QuestLogHarness(now: at(cairo, 2026, 10, 5, 9, 1)); // just after work starts: nothing is due yet
      await pumpApp(tester);
      expect(bloc.state.snapshot!.routines.where((v) => v.status is StatusDue), isEmpty);
      final next = bloc.state.snapshot!.nextUp!;
      expect(next.types, isNotEmpty);
      final targets = shortcutTargets(bloc.state.snapshot);
      await chord(tester, LogicalKeyboardKey.enter);
      expect(bloc.completed, unorderedEquals(targets));
      expect(bloc.completed.toSet(), next.types);
      expect(bloc.completed, hasLength(next.types.length));
    });

    platformTest('Ctrl+Enter prefers routines that are due now', TargetPlatform.windows, (tester) async {
      await pumpApp(tester);
      h.clock.advance(const Duration(minutes: 25));
      bloc.add(const CycleRefreshRequested());
      await tester.pump(const Duration(seconds: 1));
      final due = [
        for (final v in bloc.state.snapshot!.routines)
          if (v.status is StatusDue) v.type,
      ];
      expect(due, isNotEmpty);
      bloc.reset();
      await chord(tester, LogicalKeyboardKey.enter);
      expect(bloc.completed, unorderedEquals(due));
    });

    platformTest('Ctrl+Shift+S snoozes the snoozable target routines', TargetPlatform.windows, (tester) async {
      await pumpApp(tester);
      final expected = snoozeTargets(bloc.state.snapshot);
      expect(expected, isNotEmpty);
      await chord(tester, LogicalKeyboardKey.keyS, shift: true);
      expect(bloc.snoozed, unorderedEquals(expected));
      expect(bloc.completed, isEmpty);
    });

    platformTest('Ctrl+L logs one water tap through the hydration routine', TargetPlatform.windows, (tester) async {
      await pumpApp(tester);
      await chord(tester, LogicalKeyboardKey.keyL);
      final event = bloc.seen.whereType<RoutineCompleted>().single;
      expect(event.type, RoutineType.hydration);
      expect(event.waterMl, isNull); // the settings per-tap amount
    });

    platformTest('Done, Snooze and Log water are disabled when there is nothing to act on', TargetPlatform.windows, (
      tester,
    ) async {
      // Saturday night: off duty, no next-up.
      h = QuestLogHarness(now: at(cairo, 2026, 10, 10, 22));
      await pumpApp(tester);
      expect(bloc.state.snapshot!.onDuty, isFalse);
      await chord(tester, LogicalKeyboardKey.enter);
      await chord(tester, LogicalKeyboardKey.keyS, shift: true);
      expect(bloc.completed, isEmpty);
      expect(bloc.snoozed, isEmpty);
      // Hydration is still enabled, so Log water works off duty (as the card's Done does).
      await chord(tester, LogicalKeyboardKey.keyL);
      expect(bloc.completed, [RoutineType.hydration]);
    });

    platformTest('Log water is disabled when hydration is off', TargetPlatform.windows, (tester) async {
      await pumpApp(tester, routines: [Routine.defaults.first.copyWith(enabled: false)]);
      await chord(tester, LogicalKeyboardKey.keyL);
      expect(bloc.completed, isEmpty);
    });

    platformTest('Ctrl+W hides to the tray', TargetPlatform.windows, (tester) async {
      await pumpApp(tester);
      await chord(tester, LogicalKeyboardKey.keyW);
      expect(shell.hides, 1);
    });

    platformTest('Ctrl+Shift+F toggles the focus Shield', TargetPlatform.windows, (tester) async {
      await pumpApp(tester);
      await chord(tester, LogicalKeyboardKey.keyF, shift: true);
      expect(shieldToggles, [false]);
    });

    platformTest('during onboarding everything but the cheat sheet is disabled', TargetPlatform.windows, (
      tester,
    ) async {
      await pumpApp(tester, initial: '/onboarding');
      await chord(tester, LogicalKeyboardKey.digit2);
      await chord(tester, LogicalKeyboardKey.keyL);
      await chord(tester, LogicalKeyboardKey.keyW);
      await chord(tester, LogicalKeyboardKey.keyF, shift: true);
      expect(path(), '/onboarding');
      expect(bloc.completed, isEmpty);
      expect(shell.hides, 0);
      expect(shieldToggles, isEmpty);
      await chord(tester, LogicalKeyboardKey.slash);
      expect(find.byType(ShortcutsDialog), findsOneWidget);
    });
  });

  group('Break page', () {
    platformTest('Ctrl+Enter completes only the current step', TargetPlatform.windows, (tester) async {
      await pumpApp(tester);
      unawaited(router.push<void>('/break?types=hydration,eyeRest'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      bloc.reset();
      // First step: hydration (default 250 ml selected).
      await chord(tester, LogicalKeyboardKey.enter);
      var events = bloc.seen.whereType<RoutineCompleted>().toList();
      expect(events.map((e) => e.type), [RoutineType.hydration]);
      expect(events.single.waterMl, kDefaultWaterMl);
      expect(path(), '/break'); // the eye rest step is still pending
      // Second step: eye rest.
      await chord(tester, LogicalKeyboardKey.enter);
      events = bloc.seen.whereType<RoutineCompleted>().toList();
      expect(events.map((e) => e.type), [RoutineType.hydration, RoutineType.eyeRest]);
      expect(path(), '/');
    });

    platformTest('Log uses the selected amount', TargetPlatform.windows, (tester) async {
      await pumpApp(tester);
      unawaited(router.push<void>('/break?types=hydration'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('500 ml'));
      await tester.pump();
      bloc.reset();
      await chord(tester, LogicalKeyboardKey.enter);
      expect(bloc.seen.whereType<RoutineCompleted>().single.waterMl, 500);
    });

    platformTest('Done and Snooze do not leak to the Today reminders from the Break page', TargetPlatform.windows, (
      tester,
    ) async {
      await pumpApp(tester);
      unawaited(router.push<void>('/break?types=stretch'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      bloc.reset();
      await chord(tester, LogicalKeyboardKey.keyS, shift: true);
      expect(bloc.snoozed, isEmpty);
    });

    platformTest('Esc leaves the Break page', TargetPlatform.windows, (tester) async {
      await pumpApp(tester);
      unawaited(router.push<void>('/break?types=stretch'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BreakPage), findsNothing);
      expect(path(), '/');
    });

    platformTest('Ctrl+3 from the Break page pops back into the shell and goes to History', TargetPlatform.windows, (
      tester,
    ) async {
      await pumpApp(tester);
      unawaited(router.push<void>('/break?types=stretch'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BreakPage), findsOneWidget);
      await chord(tester, LogicalKeyboardKey.digit3);
      expect(find.byType(BreakPage), findsNothing);
      expect(path(), '/history');
      expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex, 2);
    });

    platformTest('Ctrl+3 on a Break page that is the only route falls back to go', TargetPlatform.windows, (
      tester,
    ) async {
      await pumpApp(tester, initial: '/break?types=stretch');
      expect(find.byType(NavigationRail), findsNothing);
      await chord(tester, LogicalKeyboardKey.digit3);
      expect(path(), '/history');
    });
  });

  group('cheat sheet', () {
    platformTest(
      'Ctrl+/ opens it, lists every binding with Windows key caps, and Esc closes it',
      TargetPlatform.windows,
      (tester) async {
        await pumpApp(tester);
        await chord(tester, LogicalKeyboardKey.slash);
        expect(find.byType(ShortcutsDialog), findsOneWidget);
        final l = AppLocalizationsEn();
        for (final b in AppBindings.all) {
          expect(find.text(b.label(l)), findsWidgets, reason: b.label(l));
          for (final cap in b.caps(TargetPlatform.windows)) {
            expect(find.text(cap), findsWidgets, reason: '$cap for ${b.label(l)}');
          }
        }
        for (final g in ShortcutGroup.values) {
          expect(find.text(g.title(l).toUpperCase()), findsOneWidget);
        }
        // Modal: other shortcuts stand down while it is open.
        await chord(tester, LogicalKeyboardKey.digit2);
        expect(path(), '/');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(ShortcutsDialog), findsNothing);
        await chord(tester, LogicalKeyboardKey.digit2);
        expect(path(), '/quest');
      },
    );

    platformTest('in Arabic it is localized and the key caps stay left-to-right', TargetPlatform.windows, (
      tester,
    ) async {
      await pumpApp(tester, locale: const Locale('ar'));
      await chord(tester, LogicalKeyboardKey.slash);
      final l = AppLocalizationsAr();
      expect(find.text(l.shortcutsTitle), findsOneWidget);
      for (final b in AppBindings.all) {
        expect(find.text(b.label(l)), findsWidgets, reason: b.label(l));
      }
      final cap = find.text('Ctrl').first;
      expect(Directionality.of(tester.element(cap)), TextDirection.ltr);
      expect(Directionality.of(tester.element(find.text(l.shortcutsTitle))), TextDirection.rtl);
    });

    platformTest('uses Command glyphs on macOS', TargetPlatform.macOS, (tester) async {
      await pumpApp(tester);
      await chord(tester, LogicalKeyboardKey.slash);
      expect(find.byType(ShortcutsDialog), findsOneWidget);
      expect(find.text('⌘'), findsWidgets);
      expect(find.text('⇧'), findsWidgets);
      expect(find.text('↩'), findsOneWidget);
      expect(find.text('Ctrl'), findsNothing);
    });
  });

  group('macOS', () {
    late PlatformMenuDelegate original;
    late _FakeMenuDelegate menu;

    setUp(() {
      original = WidgetsBinding.instance.platformMenuDelegate;
      menu = _FakeMenuDelegate();
      WidgetsBinding.instance.platformMenuDelegate = menu;
    });

    tearDown(() => WidgetsBinding.instance.platformMenuDelegate = original);

    platformTest('Command is the modifier', TargetPlatform.macOS, (tester) async {
      await pumpApp(tester);
      await chord(tester, LogicalKeyboardKey.digit2, command: false);
      expect(path(), '/');
      await chord(tester, LogicalKeyboardKey.digit2);
      expect(path(), '/quest');
    });

    platformTest('the menu bar is present only on macOS and carries every binding', TargetPlatform.macOS, (
      tester,
    ) async {
      await pumpApp(tester, native: null);
      expect(find.byType(PlatformMenuBar), findsOneWidget);
      final l = AppLocalizationsEn();
      expect(
        [for (final m in menu.menus) (m as PlatformMenu).label],
        [l.appTitle, l.menuGo, l.menuReminders, l.menuWindow, l.menuHelp],
      );

      final items = [
        for (final m in _flatten(menu.menus))
          if (m is! PlatformProvidedMenuItem) m,
      ];
      for (final b in AppBindings.all) {
        final match = items.where((i) => _carries(i, b));
        expect(match, isNotEmpty, reason: b.label(l));
        expect(match.every((i) => i.onSelectedIntent.runtimeType == b.intent.runtimeType), isTrue, reason: b.label(l));
      }
      // The ⌘, item in the app menu and the cheat sheet entry in Help.
      expect(items.any((i) => i.label == l.menuAppSettings), isTrue);
      expect(items.any((i) => i.label == l.shortcutShowShortcuts && i.shortcut != null), isTrue);
    });

    platformTest(
      'a shortcut fires once: Flutter leaves the key to the menu, and selecting the item runs the action',
      TargetPlatform.macOS,
      (tester) async {
        await pumpApp(tester, native: null);
        // No Flutter-side shortcuts on macOS: the native key equivalent is the only trigger.
        final shortcuts = tester.widget<Shortcuts>(
          find.descendant(of: find.byType(AppShortcuts), matching: find.byType(Shortcuts)).first,
        );
        expect(shortcuts.shortcuts, isEmpty);
        await chord(tester, LogicalKeyboardKey.digit2);
        expect(path(), '/');

        // The menu item sends the same intent through Actions.
        final item = _flatten(menu.menus)
            .whereType<PlatformMenuItem>()
            .firstWhere((i) => i.onSelectedIntent == AppBindings.questLog.intent);
        Actions.invoke(FocusManager.instance.primaryFocus!.context!, item.onSelectedIntent!);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(path(), '/quest');

        bloc.reset();
        final expected = shortcutTargets(bloc.state.snapshot);
        final done = _flatten(menu.menus)
            .whereType<PlatformMenuItem>()
            .firstWhere((i) => _carries(i, AppBindings.done));
        Actions.invoke(FocusManager.instance.primaryFocus!.context!, done.onSelectedIntent!);
        await tester.pump();
        expect(bloc.completed, unorderedEquals(expected)); // once, not twice
      },
    );

    platformTest('menu items reflect enabled state', TargetPlatform.macOS, (tester) async {
      h = QuestLogHarness(now: at(cairo, 2026, 10, 10, 22)); // off duty: nothing to complete or snooze
      await pumpApp(tester, native: null);
      PlatformMenuItem byIntent(Type t) =>
          _flatten(menu.menus)
              .whereType<PlatformMenuItem>()
              .firstWhere((i) => _carries(i, AppBindings.all.firstWhere((b) => b.intent.runtimeType == t)));
      expect(byIntent(CompleteNextIntent).onSelectedIntent, isNull);
      expect(byIntent(SnoozeNextIntent).onSelectedIntent, isNull);
      expect(byIntent(LogWaterIntent).onSelectedIntent, isNotNull);
      expect(byIntent(ShowShortcutsIntent).onSelectedIntent, isNotNull);
    });

    platformTest(
      'the router mounting in a build outside a frame does not rebuild during that build',
      TargetPlatform.macOS,
      (tester) async {
        // On launch the root widget is attached from a timer (idle phase, not inside a frame) and the router sets its
        // initial route while it is first built: the menu refresh must wait for the frame. Reproduced by inserting the
        // router (inside the splash overlay, as the app does) and running that build directly.
        final showRouter = ValueNotifier(false);
        addTearDown(showRouter.dispose);
        await pumpApp(
          tester,
          native: null,
          wrap: (child) => SplashOverlay(
            show: false,
            onFinished: () {},
            child: ValueListenableBuilder<bool>(
              valueListenable: showRouter,
              builder: (_, show, _) => show ? child : const SizedBox.shrink(),
            ),
          ),
        );
        showRouter.value = true;
        expect(SchedulerBinding.instance.schedulerPhase, SchedulerPhase.idle);
        tester.binding.buildOwner!.buildScope(tester.binding.rootElement!);
        expect(tester.takeException(), isNull);
        await tester.pump();
        expect(find.byType(PlatformMenuBar), findsOneWidget);
      },
    );

    platformTest('there is no menu bar off macOS', TargetPlatform.windows, (tester) async {
      await pumpApp(tester, native: null);
      expect(find.byType(PlatformMenuBar), findsNothing);
      expect(menu.sets, 0);
    });
  });
}
