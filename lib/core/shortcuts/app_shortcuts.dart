import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:knight_rise/core/di/injection.dart';
import 'package:knight_rise/core/feedback/haptics.dart';
import 'package:knight_rise/core/platform/platform_shell.dart';
import 'package:knight_rise/core/shortcuts/app_bindings.dart';
import 'package:knight_rise/core/shortcuts/app_intents.dart';
import 'package:knight_rise/core/shortcuts/app_menu_bar.dart';
import 'package:knight_rise/core/shortcuts/shell_navigation.dart';
import 'package:knight_rise/core/shortcuts/shortcuts_dialog.dart';
import 'package:knight_rise/features/cycle/presentation/bloc/cycle_bloc.dart';
import 'package:knight_rise/features/routines/domain/entities/routine.dart';
import 'package:knight_rise/features/scheduler/domain/entities/cycle_snapshot.dart';
import 'package:knight_rise/features/scheduler/domain/entities/planner_models.dart';
import 'package:knight_rise/features/shield/domain/usecases/shield_usecases.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Starts a focus Shield when [active] is false, ends the active one when true.
typedef FocusShieldToggle = Future<void> Function({required bool active});

/// Location paths of the four shell branches, in branch order.
const List<String> kBranchPaths = ['/', '/quest', '/history', '/settings'];

/// Whether [path] is shown inside the shell (as opposed to a full-screen route such as `/break`).
bool isShellPath(String path) => path == '/' || path == '/quest' || path == '/history' || path.startsWith('/settings');

/// Which routines Done / Snooze act on, from [snapshot].
///
/// The rule: routines that are due right now win (the Today card's "Claim break" completes exactly those);
/// otherwise the routines of the next-up reminder, which is what the notification's Done and Snooze buttons act
/// on. Nothing while off duty, with no next-up, or with no snapshot yet.
List<RoutineType> shortcutTargets(CycleSnapshot? snapshot) {
  if (snapshot == null) return const [];
  final due = [
    for (final v in snapshot.routines)
      if (v.routine.enabled && v.status is StatusDue) v.type,
  ];
  if (due.isNotEmpty) return due;
  final next = snapshot.nextUp;
  if (next == null || !snapshot.onDuty) return const [];
  return [
    for (final v in snapshot.routines)
      if (v.routine.enabled && next.types.contains(v.type)) v.type,
  ];
}

/// The subset of [shortcutTargets] that Snooze applies to: those that can be snoozed and are due or upcoming
/// (the same condition as the routine card's Snooze button).
List<RoutineType> snoozeTargets(CycleSnapshot? snapshot) {
  if (snapshot == null) return const [];
  final targets = shortcutTargets(snapshot);
  return [
    for (final type in targets)
      if (snapshot.viewOf(type) case final v? when v.canSnooze && (v.status is StatusDue || v.status is StatusUpcoming))
        type,
  ];
}

/// App-wide keyboard shortcuts, actions and (on macOS) the native menu bar. Mount it once, in the
/// `MaterialApp.router` builder: inside Localizations, below the `CycleBloc` provider, above the navigator.
///
/// * The key table is [AppBindings]; the cheat sheet and the macOS menus are generated from the same table.
/// * Every intent has one `Action` here. Disabled actions (nothing to complete, hydration off, onboarding, the
///   cheat sheet open) are skipped by `Shortcuts`, so the key falls through untouched.
/// * Navigation goes through [ShellNavigation] (the `AppShell` registers its shell in a [ShellNavigationScope]
///   this widget provides): `goBranch` keeps each branch's stack; from a full-screen route the route is popped
///   first. Without a mounted shell it falls back to `go`.
/// * Navigation shortcuts also fire while a text field has focus: Ctrl/Cmd + digit and `,` are not editing
///   keys. Select-all, copy, paste, cut and undo (A, C, V, X, Z) are not bound.
/// * On macOS the menu bar owns the key equivalents (NSMenu consumes them before Flutter sees them), so the
///   `Shortcuts` map is left empty there: each combination fires exactly once, via the menu item's
///   `onSelectedIntent`, which invokes the same actions.
class AppShortcuts extends StatefulWidget {
  const AppShortcuts({
    required this.router,
    required this.child,
    super.key,
    this.platformShell,
    this.toggleFocusShield,
    this.nativeMenu,
  });

  final GoRouter router;
  final Widget child;

  /// Window control behind Hide to tray; the DI one by default (none: the action does nothing).
  final PlatformShell? platformShell;

  /// Focus Shield on/off; the DI use cases by default.
  final FocusShieldToggle? toggleFocusShield;

  /// Whether the native macOS menu bar carries the shortcuts. Defaults to running on macOS.
  final bool? nativeMenu;

  @override
  State<AppShortcuts> createState() => _AppShortcutsState();
}

class _AppShortcutsState extends State<AppShortcuts> {
  final _navigation = ShellNavigation();
  late final Map<Type, Action<Intent>> _actions = {
    GoToBranchIntent: _Gated<GoToBranchIntent>(enabled: (_) => _navigationEnabled, run: (i) => _goToBranch(i.index)),
    OpenSettingsIntent: _Gated<OpenSettingsIntent>(enabled: (_) => _navigationEnabled, run: (_) => _goToBranch(3)),
    CompleteNextIntent: _Gated<CompleteNextIntent>(
      enabled: (_) => _onShell && _targets.isNotEmpty,
      run: (_) => _done(),
    ),
    SnoozeNextIntent: _Gated<SnoozeNextIntent>(
      enabled: (_) => _onShell && _snoozable.isNotEmpty,
      run: (_) => _snooze(),
    ),
    LogWaterIntent: _Gated<LogWaterIntent>(enabled: (_) => _hydrationOn, run: (_) => _logWater()),
    HideToTrayIntent: _Gated<HideToTrayIntent>(enabled: (_) => _active, run: (_) => _hide()),
    ShowShortcutsIntent: _Gated<ShowShortcutsIntent>(
      enabled: (_) => !shortcutsDialogOpen.value,
      run: (_) => _cheatSheet(),
    ),
    ToggleFocusShieldIntent: _Gated<ToggleFocusShieldIntent>(
      enabled: (_) => _active && _snapshot != null,
      run: (_) => _toggleShield(),
    ),
  };

  CycleBloc? _bloc;
  StreamSubscription<CycleState>? _sub;
  Object? _signature;

  bool get _native => widget.nativeMenu ?? defaultTargetPlatform == TargetPlatform.macOS;

  /// Path of the topmost route. The route information (`uri`) does not follow imperative pushes such as `/break`,
  /// so this reads the last match.
  String get _path {
    final matches = widget.router.routerDelegate.currentConfiguration;
    return matches.isEmpty ? '/' : matches.last.matchedLocation;
  }

  /// Not on the first-run flow and no modal cheat sheet over the app.
  bool get _active => _path != '/onboarding' && !shortcutsDialogOpen.value;
  bool get _navigationEnabled => _active;
  bool get _onShell => _active && isShellPath(_path);

  CycleSnapshot? get _snapshot => _bloc?.state.snapshot;
  List<RoutineType> get _targets => shortcutTargets(_snapshot);
  List<RoutineType> get _snoozable => snoozeTargets(_snapshot);
  bool get _hydrationOn => _active && (_snapshot?.viewOf(RoutineType.hydration)?.routine.enabled ?? false);

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_refreshMenus);
    shortcutsDialogOpen.addListener(_refreshMenus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Watching the instance: it is replaced when the app's providers are recreated (timezone change).
    final bloc = context.watch<CycleBloc>();
    if (!identical(bloc, _bloc)) {
      unawaited(_sub?.cancel());
      _bloc = bloc;
      _sub = bloc.stream.listen((_) => _refreshMenus());
    }
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_refreshMenus);
    shortcutsDialogOpen.removeListener(_refreshMenus);
    unawaited(_sub?.cancel());
    super.dispose();
  }

  /// Menu items reflect enabled state, so rebuild when that changes (not on every snapshot).
  void _refreshMenus() {
    if (!mounted || !_native) return;
    final signature = Object.hashAll([
      for (final i in menuIntents) _actions[i.runtimeType]!.isEnabled(i),
      _snapshot?.activeShield != null,
    ]);
    if (signature == _signature) return;
    _signature = signature;
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      scheduler.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  // ------------------------------------------------------------ actions

  void _goToBranch(int index) {
    // A full-screen route (the Break page) is popped back into the shell first.
    if (!isShellPath(_path) && widget.router.canPop()) widget.router.pop();
    if (!_navigation.goBranch(index)) widget.router.go(kBranchPaths[index]);
  }

  /// Same as the Today card: haptic, then one completion per routine.
  void _done() {
    final bloc = _bloc;
    final targets = _targets;
    if (bloc == null || targets.isEmpty) return;
    context.haptic(HapticKind.success);
    for (final type in targets) {
      bloc.add(RoutineCompleted(type));
    }
  }

  void _snooze() {
    final bloc = _bloc;
    final targets = _snoozable;
    if (bloc == null || targets.isEmpty) return;
    context.haptic(HapticKind.light);
    for (final type in targets) {
      bloc.add(RoutineSnoozed(type));
    }
  }

  /// One tap of the hydration routine: the amount comes from settings (no `waterMl`).
  void _logWater() {
    context.haptic(HapticKind.success);
    _bloc?.add(const RoutineCompleted(RoutineType.hydration));
  }

  void _hide() {
    final shell = widget.platformShell ?? (getIt.isRegistered<PlatformShell>() ? getIt<PlatformShell>() : null);
    if (shell != null) unawaited(shell.hideToTray());
  }

  void _cheatSheet() {
    // The dialog needs a Navigator; this widget sits above it.
    final navigator = widget.router.routerDelegate.navigatorKey.currentContext;
    if (navigator != null) unawaited(showShortcutsDialog(navigator));
  }

  Future<void> _toggleShield() async {
    final active = _snapshot?.activeShield != null;
    context.haptic(HapticKind.success);
    final toggle = widget.toggleFocusShield;
    if (toggle != null) {
      await toggle(active: active);
      return;
    }
    if (active) {
      await getIt<EndShield>()();
    } else {
      await getIt<StartShield>()(ShieldPreset.min25);
    }
  }

  @override
  Widget build(BuildContext context) {
    final platform = defaultTargetPlatform;
    Widget result = ShellNavigationScope(
      navigation: _navigation,
      child: Actions(
        actions: _actions,
        child: Shortcuts(shortcuts: _native ? const {} : AppBindings.shortcuts(platform), child: widget.child),
      ),
    );
    if (_native) {
      result = PlatformMenuBar(
        menus: buildAppMenus(
          l: AppLocalizations.of(context),
          platform: platform,
          intentFor: (intent) => _actions[intent.runtimeType]!.isEnabled(intent) ? intent : null,
        ),
        child: result,
      );
    }
    return result;
  }
}

/// An [Action] whose availability and effect are closures over the host state.
class _Gated<T extends Intent> extends Action<T> {
  _Gated({required this.enabled, required this.run});

  final bool Function(T intent) enabled;
  final void Function(T intent) run;

  @override
  bool isEnabled(T intent) => enabled(intent);

  @override
  Object? invoke(T intent) {
    run(intent);
    return null;
  }
}
