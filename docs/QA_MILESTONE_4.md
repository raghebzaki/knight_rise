# Milestone 4 — Device QA checklist

Run on the device matrix: Pixel (stock Android 14+), Samsung (One UI), Xiaomi
(HyperOS), iPhone (iOS 17+). Tick each line; note the device for any failure.
Automated coverage: 735 tests including the M4 gate (`test/gate/m4_gate_test.dart`)
and the accessibility audit (`test/accessibility/`).

## 0. Setup

- Android: `flutter build apk --flavor prod --release` (R8 on) and
  `flutter run --flavor dev`. Install both; they sit side by side
  (Knight Rise / Knight Rise Dev, amber icon).
- iOS: `flutter run --release` (prod) on a device signed with your team.
- Prod builds have **no** gallery / diagnostics buttons on Today.

## 1. Quest Log (tab 2)

- [ ] Day 1 on a fresh install: "Your quest begins today" card, Page rank, "No streak yet". The card disappears after the first action.
- [ ] Rings match Today; hydration ring and labels are in ml ("1,250 / 2,000 ml").
- [ ] Each routine card shows "Last at HH:MM" after a Done, "Disabled" when the routine is off.
- [ ] Focus time today grows while a Shield runs (updates within a minute).

## 2. Water logger and undo

- [ ] 150 / 250 / 500 ml chips log that amount; a SnackBar offers Undo.
- [ ] Undo removes exactly that entry (ring and "ml today" drop back).
- [ ] The SnackBar disappears by itself after ~5 s; the entry stays.
- [ ] After an undo, the next hydration reminder time is the same as before the log.

## 3. History (tab 3)

- [ ] 7 / 30 days toggle; chips All / Hydration / Quick stretch / Eye rest recolour the bars and rescope the tiles.
- [ ] Weekend bars are dimmed; the dashed goal line matches Settings › Streak goal.
- [ ] Tapping a bar shows date and status; the table toggle lists every day.
- [ ] Fresh install: "Your history starts after your first full day…" until the first midnight passes.

## 4. Streaks, ranks and the overnight path

- [ ] Leave the app **closed overnight** (no taps). Next morning, open it: yesterday appears in History and the streak counts it.
- [ ] Complete a day **only through notification Done buttons**, never opening the app. Next morning: the day is qualified.
- [ ] Rank-up: the day the streak reaches 3 (Squire) or 7 (Knight), the "Rank up!" dialog appears **once**, on whichever tab opens first — including the next morning if the goal was reached via notifications. It does not reappear after closing and reopening.
- [ ] A "Day off" today does not break the streak.
- [ ] Settings › Streak goal 90 %: today's goal line and "Reach 90 %…" text update; past days keep their original goal.

## 5. Polish and accessibility

- [ ] Haptics on Done / Claim break / water / Shield end; Settings › Haptic feedback off silences all of them.
- [ ] Rings sweep in and pulse once on reaching 100 %; History bars grow in.
- [ ] System "Remove animations" (Android) / "Reduce Motion" (iOS): no sweep, pulse or growth; everything still appears.
- [ ] Font size at maximum (200 %): Today, Quest Log, History, Settings show no clipped or overlapping text; "Claim break" stacks under its title.
- [ ] TalkBack / VoiceOver: rings read their values ("Hydration 1,250 / 2,000 ml…"); the chart reads its summary; water chips read "Log 250 ml of water"; the next-up countdown announces at most once a minute.
- [ ] Android developer option "Force RTL layout direction": layouts mirror, nothing overlaps.
- [ ] Stretch is neon lime everywhere (rings, cards, chart filter, notification accent if any).
- [ ] Turn off airplane mode / network: nothing changes (the app is fully offline).

## 5b. Arabic & English

- [ ] Fresh install on a phone set to **Arabic**: onboarding opens in Arabic, right-to-left. On a phone set to English or any other language (e.g. French): English.
- [ ] Onboarding step 0: tap العربية, and the whole flow switches to Arabic and RTL at once; tap English to switch back. Choices made on later steps survive a switch.
- [ ] Settings › Language: switching works at any time and every tab follows (Today, Quest Log, History, Settings).
- [ ] The chosen language survives killing the app and a **reboot**, and the first frame is already in that language (no English flash).
- [ ] Arabic: text is joined (no gaps between letters), numbers use Latin digits, ranks read مُتدرب / مُحارب / فارس / فارس أسطوري, plurals read naturally ("سلسلة 5 أيام", "سلسلة 14 يومًا").
- [ ] Arabic in RTL: back arrows and list chevrons point the right way, sliders and progress fill from the right, the History chart and time pickers are readable, nothing overlaps at 200 % font size.
- [ ] Notifications stay in English in both languages (expected for v1.0; localized in v1.1).

## 6. Release build and updates (Android prod, R8)

- [ ] Install the prod release, let reminders schedule, **reboot**: reminders still fire.
- [ ] **Update install:** install build N, let reminders schedule, install build N+1 (bump `+build`) over it **without opening it**, wait for the next reminder: it fires. Then reboot: still fires.
- [ ] Notification small icon is the shield (not a blank square).
- [ ] Splash: Midnight background with the icon, no white flash (Android 12+ and older); the hand-off to the first screen shows no colour step.
- [ ] Animated splash plays on a normal cold start. Kill the app, then tap a reminder notification: **no** animated splash, the break screen opens at once (Android and iOS).
- [ ] Device health › open settings buttons open **this** app's pages (prod and dev).

## 7. Regression (M2 / M3)

- [ ] Run `flutter test integration_test/notification_schedule_test.dart -d <device>` on one Android and one iOS device.
- [ ] Shield start / extend / end, recovery ping, day-off and working-late chips behave as in M3.

## 8. Dogfooding log (one week)

| Day | Device | Reminders on time? | Missed / duplicate? | Streak & history correct next morning? | Notes |
| --- | --- | --- | --- | --- | --- |
| Mon | | | | | |
| Tue | | | | | |
| Wed | | | | | |
| Thu | | | | | |
| Fri | | | | | |
| Sat | | | | | |
| Sun | | | | | |

**Exit:** a week with no missed-schedule bugs on every matrix device, and both store builds approved.

## Report back

Device + OS, the failing line, what you saw vs. expected, and a screenshot or
screen recording. For timing issues, include Settings › Device health status
and (dev build) the diagnostics screen's last reconcile runs.
