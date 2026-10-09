import 'package:flutter/widgets.dart';

/// Switches to the shell branch at [index] (0 Today, 1 Quest Log, 2 History, 3 Settings).
class GoToBranchIntent extends Intent {
  const GoToBranchIntent(this.index);

  /// Branch index, in `AppShell` order.
  final int index;
}

/// Marks the next reminder done (see `AppShortcuts` for which routines that is).
class CompleteNextIntent extends Intent {
  const CompleteNextIntent();
}

/// Snoozes the next reminder's routines that can be snoozed.
class SnoozeNextIntent extends Intent {
  const SnoozeNextIntent();
}

/// Logs one tap of water (the per-tap amount from settings).
class LogWaterIntent extends Intent {
  const LogWaterIntent();
}

/// Hides the window to the tray (desktop; nothing happens on mobile).
class HideToTrayIntent extends Intent {
  const HideToTrayIntent();
}

/// Opens the keyboard shortcut cheat sheet.
class ShowShortcutsIntent extends Intent {
  const ShowShortcutsIntent();
}

/// Opens Settings (same destination as `GoToBranchIntent(3)`).
class OpenSettingsIntent extends Intent {
  const OpenSettingsIntent();
}

/// Starts a 25-minute focus Shield, or ends the active one.
class ToggleFocusShieldIntent extends Intent {
  const ToggleFocusShieldIntent();
}
