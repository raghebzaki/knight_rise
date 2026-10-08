# Milestone 3 — Device QA checklist

Gate: **Shield start / end / extend, a Shield started while a reminder is due, and work-hours edits produce exactly the expected pending notifications** — verified on device with Diagnostics and the on-device integration test.

Devices: Pixel (stock Android 13+), Samsung (One UI), Xiaomi (HyperOS), iPhone (iOS 15+). Use a **dev** build so Diagnostics (bug icon) is available. Record device, OS version, build and time for every failure.

## 0. Setup

- [ ] `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs`, `cd ios && pod install`.
- [ ] Test **upgrade**: install over the Milestone 2 build → app opens on Home (no onboarding); Settings and data intact.
- [ ] Test **fresh install**: uninstall, install → onboarding appears (section 1).
- [ ] Run the on-device test during work hours: `flutter test integration_test/notification_schedule_test.dart -d <device>` → passes (it skips itself outside work hours or without notification permission).

## 1. Onboarding ("Take the Oath") — fresh install

- [ ] Welcome → Begin; progress bar shows 4 segments.
- [ ] Routines: switching all three off disables Next with a hint; interval chips change the selection.
- [ ] Work hours: Sun–Thu / Mon–Fri / Custom days; start/end pickers (24 h); end before start or < 30 min blocks Next.
- [ ] Oath: Enable reminders → system prompt (Android 13+/iOS); deny → "blocked" hint; Take the Oath still works.
- [ ] System back on steps 2–4 goes to the previous step; on step 1 leaves the app.
- [ ] After Take the Oath → Home; Diagnostics shows a `manual` run and pending reminders matching the chosen routines/hours.
- [ ] Kill and relaunch → Home (onboarding not shown again).

## 2. Shield

- [ ] Shield button visible only during work hours; sheet shows Focus 25, Meeting 50, Until I turn it off, Custom (15–180 min).
- [ ] Start **Focus 25** → banner with countdown; routine cards show "Shielded until HH:MM"; Diagnostics: no pending reminder inside the Shield, one **recovery** entry at the end if any reminder was held back; "Recovery ping at HH:MM" shown only then.
- [ ] Android: ongoing "Shield active — reminders paused until HH:MM" notification with a live countdown; cannot be swiped away; disappears at the end time.
- [ ] **+15 min** → banner, ongoing notification and recovery move by 15 min.
- [ ] **End** in the banner → banner and ongoing notification gone; recovery ping arrives ~1 min later ("Shield down — Waiting: …"); regular reminders resume.
- [ ] **End Shield** from the Android notification with the app in background and with the app **killed** → same as above without opening the app.
- [ ] Start a Shield while a routine shows **Due** → status switches to Shielded; recovery includes routines that had reminders inside the Shield.
- [ ] **Until I turn it off** → ends at the end of the current work window; no recovery ping after work.
- [ ] Settings › "Recovery ping after Shield" OFF → start a Shield → no recovery entry in Diagnostics; turning it back ON re-adds it (a `configChange` run appears).
- [ ] Merged reminders: when e.g. eye rest + hydration fire together, **no second hydration-only reminder** arrives a few minutes later.
- [ ] iOS: Shield works in-app; no ongoing notification (expected).

## 3. Today overrides (Home chips)

- [ ] **Day off today** → confirmation dialog → all of today's pending reminders gone; Home shows Off duty with the next work start; × clears it and reminders return.
- [ ] **Working late +1h** → label "+1h"; tapping again "+2h" (max +4h); pending reminders extend past the normal end; never past midnight; × restores the normal end.

## 4. Settings, Work hours, Routines

- [ ] Gear opens Settings; theme switch Midnight ↔ AMOLED applies instantly and persists.
- [ ] Work hours: per-day switches; add/edit/delete windows; overlapping or < 30 min windows show an inline error and disable Save; presets and "Copy Sunday to work days" work; leaving with unsaved changes asks; Save → Diagnostics shows a `configChange` run and new pending times.
- [ ] Split shift (e.g. 09:00–12:00 + 13:00–17:00) → no reminders 12:00–13:00; intervals restart at 13:00.
- [ ] Routines: interval slider in 5-min steps within the allowed range; daily target stepper (hydration shows ml total); Rolling vs Fixed grid; Save reschedules; turning a routine off removes its pending reminders.
- [ ] Android: "Sound & vibration" opens the system settings for that routine's channel (hydration / stretch / eye rest).

## 5. Device health

- [ ] Settings shows "All good" or "N issues"; Device health page rows match reality.
- [ ] Notifications off → Fix re-prompts, or opens the app's notification settings after a permanent denial; returning updates the row.
- [ ] Precision Timing (Android 12+): switch ON → "Alarms & reminders" screen if not allowed → allow → back in app the switch stays ON; reminders fire on the minute; switch OFF → inexact again.
- [ ] Battery optimization (Android): Fix opens the battery-optimization screen; set Unrestricted → row turns OK after returning.
- [ ] Phone-maker guide matches the device (Xiaomi / Samsung / Huawei / Oppo-Realme-OnePlus / Vivo / generic); "Open settings" opens the maker's screen or falls back to App info — never crashes.
- [ ] iOS: Background App Refresh row reflects Settings › General › Background App Refresh; Fix opens the app's Settings page.
- [ ] Home "Check device health" chip appears for warnings (not for notifications-off, which has its own card) and disappears after fixing and resuming.
- [ ] "Reminders were paused — re-armed now" banner: Android Settings › Force stop during work hours → reopen → banner appears once; dismiss hides it; the very first launch after install never shows it; a normal resume never shows it; Sunday morning after a quiet weekend does not show it.

## 6. Regression (Milestone 2)

- [ ] Done / Snooze from notifications (background and killed), break screen from a tap, reboot persistence, WorkManager `periodic` runs — spot-check on one Android device and the iPhone using `docs/QA_MILESTONE_2.md` section 3–5.

## Report back

For any failure: device + OS, section/step, expected vs. actual, Diagnostics screenshots (Status, Pending, recent runs), and `flutter logs` around the time.
