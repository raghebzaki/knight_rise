# Desktop (macOS and Windows) — QA checklist

Run on the matrix below. Tick each line; note the machine and build type for any failure.
Automated coverage: 1055 tests (`flutter test`), including shell, tray, shortcut, multi-pane, Device health and
accessibility suites; the on-demand **Desktop release** workflow (`.github/workflows/release-desktop.yaml`) analyzes
and runs the suite on macOS and Windows (unless `skip_tests`) and builds the release artifacts. Pixel goldens run locally only (`flutter test --tags golden`).

## 0. Matrix and setup

| Platform | Versions | Build types |
| --- | --- | --- |
| macOS | 13, 14, 15 on Apple Silicon; one Intel Mac if available | Release `.app` (`tool/build_macos_release.sh`) and the DMG |
| Windows | 10 22H2 and 11 | Unpackaged (`flutter build windows --release`, run `knight_rise.exe`) and MSIX sideload |

- macOS: `bash tool/build_macos_release.sh` (must print only PASS), then open `build/macos/Build/Products/Release/knight_rise.app`.
  An unsigned build may need right-click > Open the first time.
- Windows unpackaged: `flutter build windows --release`; run `build\windows\x64\runner\Release\knight_rise.exe`.
- macOS DMG: `bash tool/package_macos_dmg.sh` or the `knight-rise-macos-…` artifact; open it, drag Knight Rise to
  Applications, and check the Dock and Finder show the Knight Rise icon and name.
- Windows MSIX: download the `knight-rise-windows-…` artifact of a Desktop release run (or run `dart run msix:create` locally), then trust the
  test certificate once: open `knight_rise_test.cer` > Install Certificate > Local Machine > Place in **Trusted People**.
  Double-click `knight_rise.msix` to install. Uninstall any unpackaged copy first and remove its Run entry
  (`HKCU\Software\Microsoft\Windows\CurrentVersion\Run\KnightRise`).
- Prod builds have no gallery or diagnostics screens.

## 1. First run and the Oath

- [ ] Fresh profile opens onboarding; the language buttons switch EN/AR and RTL at once.
- [ ] Oath step, unpackaged (macOS, Windows exe): "Start Knight Rise when you sign in" switch is on by default.
- [ ] Oath step, MSIX: no switch; one line "Windows starts Knight Rise when you sign in. Change it in Startup apps." (also in Arabic).
- [ ] Finishing with the switch off leaves launch at login off (Device health shows Off).

## 2. Reminders and toasts

- [ ] A reminder shows a toast in English; set Settings > Language to Arabic: the **next** toast is Arabic (not the one already shown).
- [ ] Done and Snooze buttons on the toast act on the right routine; clicking the toast body opens the app on that reminder.
- [ ] Cold start from a toast: quit the app from the tray, trigger nothing, then (MSIX) click a toast left in Action Center: the app starts and handles the action. (Unpackaged Windows cannot do this; expected.)
- [ ] Catch-up after sleep: sleep through two reminder times and wake within 10 minutes of the latest: one merged toast appears. Wake later than 10 minutes after all of them: nothing is shown (stale ones count as missed).
- [ ] Notification permission off (macOS System Settings > Notifications): Device health says so and the link opens the right pane.

## 3. Two-hour sleep/wake battery test

Purpose: confirm the in-process engine is idle-cheap and recovers after sleep.

1. Laptop on battery at 100 % (note exact charge), brightness mid, Wi-Fi on, no other heavy apps.
2. Settings: hydration every 30 min, stretch every 45, eye rest every 20; work hours cover the whole test; no Shield.
3. Note the start time T. Keep the app running (window closed to tray).
4. Sleep schedule: at T+10 min put the machine to sleep; wake at T+40 (spans reminders). Sleep again at T+50, wake at T+75. Leave awake and idle T+75 to T+120.
5. Expected: after each wake, at most one merged toast for reminders overdue by 10 minutes or less and none for older ones; no burst; the next-reminder line in the tray is correct; Device health "Background running" says running with a recent check.
6. Record the charge at T+120 and compare with a 2 h control run without the app (same sleep schedule).
7. macOS: Activity Monitor > Energy tab: Energy Impact of knight_rise averages near zero when idle, the **App Nap** column shows Yes while hidden (the Device health App Nap row informs but is not a warning when the timer still fires). Check "12 hr Power" is negligible.
8. Windows: `powercfg /batteryreport /output %USERPROFILE%\report.html` before and after; Settings > System > Power & battery > Battery usage by app shows Knight Rise under 1 %.
9. Pass: drain within 1 percentage point of the control run; no missed fresh reminders; no duplicate toasts.

## 4. Tray, close-to-tray, single instance

- [ ] Closing the window hides it to the tray/menu bar; reminders keep firing. Quit from the tray exits the process.
- [ ] Tray status line shows the next reminder time; Focus Shield items (25 / 50) start a Shield, the menu then offers lowering it.
- [ ] Tray language follows Settings > Language after a switch.
- [ ] Unpackaged: tray item "Launch at login" toggles with a checkmark. MSIX: a disabled "Launch at login (managed by Windows)" text row, no checkbox.
- [ ] Windows: starting a second copy of the exe focuses the existing window and does not open another process.

## 5. Launch at login after a reboot

- [ ] Unpackaged Windows: Run key `KnightRise` holds `"<path>\knight_rise.exe" --autostart`; after reboot and sign-in the app is in the tray with no window shown.
- [ ] Moving the exe folder marks the setting Off in Device health until re-enabled.
- [ ] MSIX: Settings > Apps > Startup lists Knight Rise (on by default); after sign-in it starts hidden. Turning it off in Startup apps is respected; Device health shows "Managed by Windows (Startup apps)" with no warning and the link opens Startup apps.
- [ ] macOS: switch on in Device health; after reboot the app starts hidden. If macOS asks for approval, "Open Login Items" opens the right pane.

## 6. Adaptive layout

- [ ] Resize from the minimum (400x640) to about 1300 wide: bottom bar below 600, rail 600-839, labelled rail 840-1199, extended sidebar from 1200. No overflow or clipping at any width.
- [ ] Repeat in Arabic (RTL): the rail/sidebar is on the right, nothing overlaps, chevrons point correctly.
- [ ] Text scale 200 % at 400 wide: no clipped text.

## 7. Multi-pane interactions

- [ ] History at 840+ wide: hovering a bar previews its day in the detail pane; clicking pins it; clicking again or Unpin releases.
- [ ] Settings at 840+ wide: list and detail side by side. Edit a field without saving, click another list item: the discard prompt appears; Cancel stays, Discard switches. Narrow width pushes pages instead.

## 8. Keyboard shortcuts

Modifier is Command on macOS (also via the menu bar items) and Ctrl on Windows.

| Action | macOS | Windows | macOS ✓ | Windows ✓ |
| --- | --- | --- | --- | --- |
| Today | ⌘1 | Ctrl+1 | [ ] | [ ] |
| Quest Log | ⌘2 | Ctrl+2 | [ ] | [ ] |
| History | ⌘3 | Ctrl+3 | [ ] | [ ] |
| Settings tab | ⌘4 | Ctrl+4 | [ ] | [ ] |
| Open settings | ⌘, | Ctrl+, | [ ] | [ ] |
| Done (next reminder) | ⌘↩ | Ctrl+Enter | [ ] | [ ] |
| Snooze (next reminder) | ⌘⇧S | Ctrl+Shift+S | [ ] | [ ] |
| Log water | ⌘L | Ctrl+L | [ ] | [ ] |
| Start/end Focus Shield | ⌘⇧F | Ctrl+Shift+F | [ ] | [ ] |
| Hide to tray | ⌘W | Ctrl+W | [ ] | [ ] |
| Keyboard shortcuts cheat sheet | ⌘/ | Ctrl+/ | [ ] | [ ] |

- [ ] The cheat sheet lists exactly these, with the right modifier for the OS, in EN and AR.
- [ ] Esc closes the cheat sheet and dialogs and returns focus to the control that opened them.
- [ ] Each shortcut fires once (macOS: not twice via menu and key). Disabled ones (nothing to complete, hydration off, onboarding) do nothing.
- [ ] Navigation shortcuts work while a text field has focus; Ctrl/Cmd+C, V, A are untouched.
- [ ] macOS menu bar: App, Go, Reminders, Window menus show the same keys.
- [ ] Focus ring pass: Tab through Today, Quest Log, History and Settings in EN and AR; the focused control always has a clearly visible ring, order follows reading direction, nothing traps focus.

## 9. Device health and deep links

- [ ] macOS: Notifications, Login Items and Battery links open the matching System Settings panes.
- [ ] Windows: Notifications (`ms-settings:notifications`), Startup apps (`ms-settings:startupapps`), Battery saver (`ms-settings:batterysaver`) open the right pages.
- [ ] Windows notifications row says it cannot be verified (the plugin cannot read the toggle); no false alarm.
- [ ] Fixing a warning (e.g. launch at login off) with the switch clears it.

## 10. Timezone change while running

- [ ] Change the system timezone with the app running: within a minute the next-reminder time, tray status and Today use the new zone; work-hour windows follow local time; no duplicate or lost reminder.

## Known limitations

- macOS launch-at-login detection (launched by the login item) is best effort.
- Windows: the notifications toggle cannot be read, so Device health cannot verify it.
- Arabic goldens render boxes (no Arabic font in the test environment); layout is verified by widget tests instead.
- MSIX: enabling or disabling the StartupTask from inside the app (WinRT `StartupTask.RequestEnableAsync`) is a follow-up; today users change it in Windows Startup apps.
- A cold start from an MSIX toast shows the window (the toast activator does not pass `--autostart`).

## Report back

OS version + build type (exe / MSIX / macOS app), the failing line, what you saw vs. expected, a screenshot, and the
Device health status.
