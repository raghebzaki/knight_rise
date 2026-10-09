import 'package:flutter/widgets.dart';
import 'package:knight_rise/core/shortcuts/app_bindings.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Every intent a menu item can send, for tracking their enabled state.
final List<Intent> menuIntents = [for (final b in AppBindings.all) b.intent];

/// The macOS menu bar.
///
/// Items carry the shortcut from [AppBindings] and send the binding's intent through [intentFor], which returns
/// null for a disabled action (the item is then greyed out). Selecting an item invokes the same `Actions` as the
/// key does elsewhere, so no logic is duplicated.
List<PlatformMenuItem> buildAppMenus({
  required AppLocalizations l,
  required TargetPlatform platform,
  required Intent? Function(Intent intent) intentFor,
}) {
  PlatformMenuItem item(AppBinding b, {String? label}) => PlatformMenuItem(
    label: label ?? b.label(l),
    shortcut: b.activator(platform),
    onSelectedIntent: intentFor(b.intent),
  );
  PlatformProvidedMenuItem provided(PlatformProvidedMenuItemType type) => PlatformProvidedMenuItem(type: type);

  return [
    PlatformMenu(
      label: l.appTitle,
      menus: [
        PlatformMenuItemGroup(members: [provided(PlatformProvidedMenuItemType.about)]),
        PlatformMenuItemGroup(members: [item(AppBindings.openSettings, label: l.menuAppSettings)]),
        PlatformMenuItemGroup(members: [provided(PlatformProvidedMenuItemType.servicesSubmenu)]),
        PlatformMenuItemGroup(
          members: [
            provided(PlatformProvidedMenuItemType.hide),
            provided(PlatformProvidedMenuItemType.hideOtherApplications),
            provided(PlatformProvidedMenuItemType.showAllApplications),
          ],
        ),
        PlatformMenuItemGroup(members: [provided(PlatformProvidedMenuItemType.quit)]),
      ],
    ),
    PlatformMenu(
      label: l.menuGo,
      menus: [
        item(AppBindings.today),
        item(AppBindings.questLog),
        item(AppBindings.history),
        item(AppBindings.settingsTab),
      ],
    ),
    PlatformMenu(
      label: l.menuReminders,
      menus: [
        item(AppBindings.done),
        item(AppBindings.snooze),
        item(AppBindings.logWater),
        item(AppBindings.focusShield),
      ],
    ),
    PlatformMenu(
      label: l.menuWindow,
      menus: [
        PlatformMenuItemGroup(members: [item(AppBindings.hideToTray)]),
        PlatformMenuItemGroup(
          members: [
            provided(PlatformProvidedMenuItemType.minimizeWindow),
            provided(PlatformProvidedMenuItemType.zoomWindow),
          ],
        ),
        PlatformMenuItemGroup(members: [provided(PlatformProvidedMenuItemType.toggleFullScreen)]),
      ],
    ),
    PlatformMenu(label: l.menuHelp, menus: [item(AppBindings.showShortcuts)]),
  ];
}
