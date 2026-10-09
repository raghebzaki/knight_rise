import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:knight_rise/features/desktop_shell/domain/launch_at_login.dart';
import 'package:knight_rise/l10n/generated/app_localizations.dart';
import 'package:timezone/timezone.dart' as tz;

/// What a tray menu item does when chosen.
enum TrayCommand { open, shield25, shield50, endShield, toggleLaunchAtLogin, quit }

/// One row of the tray menu: a status line, an action, a checkbox, or a
/// separator.
@immutable
class TrayMenuEntry {
  const TrayMenuEntry({required this.label, this.command, this.enabled = true, this.checked}) : isSeparator = false;

  const TrayMenuEntry.separator() : label = '', command = null, enabled = false, checked = null, isSeparator = true;

  final String label;

  /// Null for the status line and separators.
  final TrayCommand? command;
  final bool enabled;

  /// Non-null renders a checkbox.
  final bool? checked;

  final bool isSeparator;

  @override
  bool operator ==(Object other) =>
      other is TrayMenuEntry &&
      other.label == label &&
      other.command == command &&
      other.enabled == enabled &&
      other.checked == checked &&
      other.isSeparator == isSeparator;

  @override
  int get hashCode => Object.hash(label, command, enabled, checked, isSeparator);

  @override
  String toString() =>
      isSeparator ? 'TrayMenuEntry.separator()' : 'TrayMenuEntry($label, $command, $enabled, $checked)';
}

/// Builds the tray menu from the current state. Pure: the caller supplies
/// time, language and data.
abstract final class TrayMenuModel {
  static List<TrayMenuEntry> build({
    required AppLocalizations l,
    required String localeName,
    required tz.Location location,
    required DateTime now,
    required LaunchAtLoginStatus launchAtLogin,
    DateTime? nextReminderAt,
    DateTime? shieldUntil,
  }) {
    String time(DateTime t) => DateFormat.jm(localeName).format(tz.TZDateTime.from(t, location));
    final shielded = shieldUntil != null && shieldUntil.isAfter(now);
    final status = shielded
        ? l.trayShieldUntil(time(shieldUntil))
        : nextReminderAt != null
        ? l.trayNextReminder(time(nextReminderAt))
        : l.trayNoReminders;
    return [
      TrayMenuEntry(label: status, enabled: false),
      const TrayMenuEntry.separator(),
      TrayMenuEntry(label: l.trayOpen, command: TrayCommand.open),
      if (shielded)
        TrayMenuEntry(label: l.trayLowerShield, command: TrayCommand.endShield)
      else ...[
        TrayMenuEntry(label: l.shieldPresetFocus, command: TrayCommand.shield25),
        TrayMenuEntry(label: l.shieldPresetMeeting, command: TrayCommand.shield50),
      ],
      const TrayMenuEntry.separator(),
      // Packaged Windows: Startup apps owns the setting, so show a disabled text row (no checkbox, which would claim
      // a state this app cannot read).
      if (launchAtLogin == LaunchAtLoginStatus.managedBySystem)
        TrayMenuEntry(label: l.trayLaunchAtLoginManaged, enabled: false)
      else
        TrayMenuEntry(
          label: l.trayLaunchAtLogin,
          command: TrayCommand.toggleLaunchAtLogin,
          enabled: launchAtLogin != LaunchAtLoginStatus.unavailable,
          checked: launchAtLogin == LaunchAtLoginStatus.enabled,
        ),
      const TrayMenuEntry.separator(),
      TrayMenuEntry(label: l.trayQuit, command: TrayCommand.quit),
    ];
  }
}
