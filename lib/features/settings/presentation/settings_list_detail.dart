import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:knight_rise/core/layout/window_size.dart';
import 'package:knight_rise/core/theme/knight_dimens.dart';
import 'package:knight_rise/core/theme/knight_tokens.dart';
import 'package:knight_rise/features/settings/presentation/settings_page.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Width of the settings list pane when the window is multi-pane.
const double kSettingsListPaneWidth = 360;

/// Coordinates unsaved-changes prompts between the list pane and the detail
/// page: a dirty editor registers [guard], and navigation inside the panes
/// asks [confirmLeave] first (a `go` replaces the page without a `PopScope`).
class SettingsPaneController {
  /// Asks whether the dirty detail page may be left; null while it is clean.
  Future<bool> Function()? guard;

  /// True when nothing is dirty or the user chose to discard.
  Future<bool> confirmLeave() async => await guard?.call() ?? true;
}

/// Present only while Settings is laid out as list-detail. Carries the
/// current [location] (for the selected item) and the [controller].
class SettingsPaneScope extends InheritedWidget {
  const SettingsPaneScope({required this.location, required this.controller, required super.child, super.key});

  /// Path of the current settings location, e.g. `/settings/work-hours`.
  final String location;
  final SettingsPaneController controller;

  /// The scope, or null in the compact (single-pane) layout.
  static SettingsPaneScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsPaneScope>();

  @override
  bool updateShouldNotify(SettingsPaneScope oldWidget) =>
      location != oldWidget.location || controller != oldWidget.controller;
}

/// Opens [path] from a settings page. In the list-detail layout it replaces
/// the detail (after the unsaved-changes guard); otherwise it pushes.
Future<void> openSettingsRoute(BuildContext context, String path) async {
  final pane = SettingsPaneScope.maybeOf(context);
  if (pane == null) {
    await context.push<void>(path);
    return;
  }
  if (pane.location == path) return;
  if (!await pane.controller.confirmLeave()) return;
  if (context.mounted) context.go(path);
}

/// Whether [path] is the selected location when the current one is
/// [location]; the routines list and its editors share a selection.
bool settingsPathSelected(String? location, String path) =>
    location != null && (location == path || (path == '/settings/routines' && location.startsWith('$path/')));

/// Registers a dirty page's discard prompt with the surrounding
/// [SettingsPaneScope] (no-op when compact). Wrap the page's `PopScope`.
class SettingsDiscardGuard extends StatefulWidget {
  const SettingsDiscardGuard({required this.dirty, required this.confirm, required this.child, super.key});

  final bool dirty;

  /// Shows the discard dialog; true means discard.
  final Future<bool> Function() confirm;
  final Widget child;

  @override
  State<SettingsDiscardGuard> createState() => _SettingsDiscardGuardState();
}

class _SettingsDiscardGuardState extends State<SettingsDiscardGuard> {
  SettingsPaneController? _controller;

  Future<bool> _ask() => widget.confirm();

  void _sync() {
    final controller = _controller;
    if (controller == null) return;
    if (widget.dirty) {
      controller.guard = _ask;
    } else if (controller.guard == _ask) {
      controller.guard = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = SettingsPaneScope.maybeOf(context)?.controller;
    if (next != _controller) {
      if (_controller?.guard == _ask) _controller?.guard = null;
      _controller = next;
    }
    _sync();
  }

  @override
  void didUpdateWidget(SettingsDiscardGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    if (_controller?.guard == _ask) _controller?.guard = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The Settings branch frame. Compact and medium: just the [child] route
/// stack, so sub-pages are pushed over the list with a back arrow. Expanded
/// and large: the settings list as a fixed start pane, a divider and the
/// [child] (the detail page) beside it.
///
/// The `/settings` route builds [SettingsHome], which is the list when
/// narrow and the placeholder when wide, so every location keeps its path and
/// a resize keeps the location.
class SettingsShell extends StatefulWidget {
  const SettingsShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  State<SettingsShell> createState() => _SettingsShellState();
}

class _SettingsShellState extends State<SettingsShell> {
  final SettingsPaneController _controller = SettingsPaneController();

  @override
  Widget build(BuildContext context) {
    if (!context.isMultiPane) return widget.child;
    return SettingsPaneScope(
      location: widget.location,
      controller: _controller,
      child: Row(
        children: [
          const SizedBox(width: kSettingsListPaneWidth, child: SettingsPage()),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

/// Content of `/settings`: the list when narrow, the placeholder when the
/// list is already in the start pane.
class SettingsHome extends StatelessWidget {
  const SettingsHome({super.key});

  @override
  Widget build(BuildContext context) =>
      SettingsPaneScope.maybeOf(context) == null ? const SettingsPage() : const _SettingsPlaceholder();
}

class _SettingsPlaceholder extends StatelessWidget {
  const _SettingsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final muted = context.knight.textMuted;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(KnightSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune, size: 48, color: muted),
              const SizedBox(height: KnightSpacing.md),
              Text(
                AppLocalizations.of(context).settingsSelectSection,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A settings sub-page that does not slide in when the list is beside it.
class SettingsRoutePage extends MaterialPage<void> {
  const SettingsRoutePage({required super.child, super.key, super.name});

  @override
  Route<void> createRoute(BuildContext context) => _SettingsRoute(this);
}

class _SettingsRoute extends MaterialPageRoute<void> {
  _SettingsRoute(SettingsRoutePage page) : super(settings: page, builder: (_) => page.child);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => context.isMultiPane ? child : super.buildTransitions(context, animation, secondaryAnimation, child);
}
