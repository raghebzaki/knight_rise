import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Lets the app-wide shortcut actions reach the [StatefulNavigationShell] without owning it.
///
/// `AppShortcuts` sits above the router's navigator, while the shell is built by a route below it. The `AppShell`
/// registers its shell here (found through [ShellNavigationScope]) on every build and unregisters on dispose, so
/// branch switches use `goBranch`, which keeps each branch's stack, instead of a plain `go`.
class ShellNavigation {
  StatefulNavigationShell? _shell;

  /// Whether a shell is currently mounted.
  bool get attached => _shell != null;

  /// Registers [shell] as the current one.
  // ignore: use_setters_to_change_properties
  void attach(StatefulNavigationShell shell) => _shell = shell;

  /// Unregisters [shell] if it is still the current one.
  void detach(StatefulNavigationShell shell) {
    if (identical(_shell, shell)) _shell = null;
  }

  /// Switches to branch [index]; re-selecting the current branch returns it to its first page, as the rail does.
  /// Returns false when no shell is mounted.
  bool goBranch(int index) {
    final shell = _shell;
    if (shell == null) return false;
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
    return true;
  }
}

/// Provides a [ShellNavigation] to the subtree (the whole router).
class ShellNavigationScope extends InheritedWidget {
  const ShellNavigationScope({required this.navigation, required super.child, super.key});

  final ShellNavigation navigation;

  /// The nearest [ShellNavigation], or null outside an `AppShortcuts`.
  static ShellNavigation? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellNavigationScope>()?.navigation;

  @override
  bool updateShouldNotify(ShellNavigationScope oldWidget) => navigation != oldWidget.navigation;
}
