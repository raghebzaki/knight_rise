import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:knight_rise/core/shortcuts/app_intents.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';

/// Sections of the cheat sheet, in display order.
enum ShortcutGroup {
  navigate,
  reminders,
  window,
  help;

  /// Localized section heading.
  String title(AppLocalizations l) => switch (this) {
    navigate => l.shortcutsGroupNavigate,
    reminders => l.shortcutsGroupReminders,
    window => l.shortcutsGroupWindow,
    help => l.shortcutsGroupHelp,
  };
}

/// Whether [platform] uses the Command key as its shortcut modifier (macOS and iOS); Control elsewhere.
bool usesCommandKey(TargetPlatform platform) => platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;

/// One keyboard binding: modifier + [key] (+ Shift) triggering [intent].
///
/// The modifier is implicit and platform-aware (see [usesCommandKey]). This table is the single source for the
/// `Shortcuts` map, the macOS menu bar and the cheat sheet, so they cannot drift apart.
@immutable
class AppBinding {
  const AppBinding({
    required this.group,
    required this.key,
    required this.intent,
    required this.label,
    this.shift = false,
  });

  final ShortcutGroup group;
  final LogicalKeyboardKey key;
  final bool shift;
  final Intent intent;

  /// Localized description shown in the cheat sheet and the menus.
  final String Function(AppLocalizations l) label;

  /// The activator for [platform]: Command on macOS / iOS, Control elsewhere.
  SingleActivator activator(TargetPlatform platform) {
    final command = usesCommandKey(platform);
    return SingleActivator(key, meta: command, control: !command, shift: shift);
  }

  /// Key caps for [platform], e.g. `[Ctrl, Shift, S]` or `[⌘, ⇧, S]`. Key caps are hardware legends and stay Latin
  /// in every language.
  List<String> caps(TargetPlatform platform) {
    final command = usesCommandKey(platform);
    return [
      if (command) '⌘' else 'Ctrl',
      if (shift)
        if (command) '⇧' else 'Shift',
      _keyCap(key, command: command),
    ];
  }

  static String _keyCap(LogicalKeyboardKey key, {required bool command}) {
    if (key == LogicalKeyboardKey.enter) return command ? '↩' : 'Enter';
    if (key == LogicalKeyboardKey.comma) return ',';
    if (key == LogicalKeyboardKey.slash) return '/';
    return key.keyLabel.toUpperCase();
  }
}

/// Every binding, in cheat sheet order.
abstract final class AppBindings {
  static final today = AppBinding(
    group: ShortcutGroup.navigate,
    key: LogicalKeyboardKey.digit1,
    intent: const GoToBranchIntent(0),
    label: (l) => l.navToday,
  );
  static final questLog = AppBinding(
    group: ShortcutGroup.navigate,
    key: LogicalKeyboardKey.digit2,
    intent: const GoToBranchIntent(1),
    label: (l) => l.navQuestLog,
  );
  static final history = AppBinding(
    group: ShortcutGroup.navigate,
    key: LogicalKeyboardKey.digit3,
    intent: const GoToBranchIntent(2),
    label: (l) => l.navHistory,
  );
  static final settingsTab = AppBinding(
    group: ShortcutGroup.navigate,
    key: LogicalKeyboardKey.digit4,
    intent: const GoToBranchIntent(3),
    label: (l) => l.navSettings,
  );
  static final openSettings = AppBinding(
    group: ShortcutGroup.navigate,
    key: LogicalKeyboardKey.comma,
    intent: const OpenSettingsIntent(),
    label: (l) => l.shortcutOpenSettings,
  );
  static final done = AppBinding(
    group: ShortcutGroup.reminders,
    key: LogicalKeyboardKey.enter,
    intent: const CompleteNextIntent(),
    label: (l) => l.shortcutDone,
  );
  static final snooze = AppBinding(
    group: ShortcutGroup.reminders,
    key: LogicalKeyboardKey.keyS,
    shift: true,
    intent: const SnoozeNextIntent(),
    label: (l) => l.shortcutSnooze,
  );
  static final logWater = AppBinding(
    group: ShortcutGroup.reminders,
    key: LogicalKeyboardKey.keyL,
    intent: const LogWaterIntent(),
    label: (l) => l.logWater,
  );
  static final focusShield = AppBinding(
    group: ShortcutGroup.reminders,
    key: LogicalKeyboardKey.keyF,
    shift: true,
    intent: const ToggleFocusShieldIntent(),
    label: (l) => l.shortcutFocusShield,
  );
  static final hideToTray = AppBinding(
    group: ShortcutGroup.window,
    key: LogicalKeyboardKey.keyW,
    intent: const HideToTrayIntent(),
    label: (l) => l.shortcutHideToTray,
  );
  static final showShortcuts = AppBinding(
    group: ShortcutGroup.help,
    key: LogicalKeyboardKey.slash,
    intent: const ShowShortcutsIntent(),
    label: (l) => l.shortcutShowShortcuts,
  );

  /// All bindings, in cheat sheet order.
  static final List<AppBinding> all = [
    today,
    questLog,
    history,
    settingsTab,
    openSettings,
    done,
    snooze,
    logWater,
    focusShield,
    hideToTray,
    showShortcuts,
  ];

  /// The `Shortcuts` map for [platform].
  static Map<ShortcutActivator, Intent> shortcuts(TargetPlatform platform) => {
    for (final b in all) b.activator(platform): b.intent,
  };
}
