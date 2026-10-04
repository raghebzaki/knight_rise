# Milestone 2 — Device QA checklist

Gate: **reminders fire within ~5 min of schedule over a work day with the app killed, after a reboot, and Done/Snooze work without opening the app.**

Devices: Pixel (stock Android 13+), Samsung (One UI), Xiaomi (HyperOS), iPhone (iOS 15+). Run each section on every device unless marked.

## 0. Setup

- [ ] Uninstall any previous build (default hours are seeded only on first install).
- [ ] `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs`, then install a **dev** debug build (`flutter run`).
- [ ] To test quickly during the day, open Diagnostics (bug icon) and keep it handy. To test outside Sun–Thu 09:00–17:00, temporarily change `WorkSchedule.standard()` or the device clock — note which you used.
- [ ] Record for each run: device, OS version, build, time zone.

## 1. First launch and permission (Task 8)

- [ ] Android 13+: no system permission dialog appears on launch; the "Enable reminders" card shows at the top of Home.
- [ ] Tap **Not now** → card hides; kill and relaunch → card is back.
- [ ] Tap **Enable** → system dialog appears. **Allow** → card disappears; Diagnostics shows a `manual` run with `added > 0` (during work hours) and pending notifications listed.
- [ ] Fresh install, tap **Enable** → **Don't allow** twice → body switches to "Notifications are off. Turn them on in system settings."; Enable no longer shows a dialog.
- [ ] Enable notifications in system settings, return to the app → card disappears without restarting.
- [ ] iOS: same flow; first Enable shows the iOS prompt; toggling in Settings and resuming updates the card.

## 2. Schedule and diagnostics (Tasks 3, 9)

- [ ] Diagnostics → Status shows the correct time zone (`Africa/Cairo`), notifications enabled, exact alarms allowed (Android 12+ reflects the "Alarms & reminders" toggle), precision timing = false.
- [ ] Pending list matches the plan: hydration every 45 min, stretch every 60 min, eye rest every 20 min from 09:00, reminders within 5 min merged ("Knight's call"), nothing outside work hours, at most 50 entries.
- [ ] **Reconcile now** twice → second run shows `added 0, cancelled 0` (idempotent).
- [ ] Change nothing, background and resume the app → a `resume` run appears.
- [ ] **Test notification in 1 min** → arrives within a few minutes (inexact; Doze may delay). After **Reconcile now** it is still pending (id 1).

## 3. Notification content and actions (Tasks 2, 4)

- [ ] Notification shows the Knight Rise icon (white shield on Android status bar), cyan accent, title/body for the routine, and **Done** / **Snooze 10m** buttons.
- [ ] A merged reminder shows "Knight's call" with both routine names.
- [ ] App **in background**: tap **Done** on a hydration reminder → notification disappears, app does not open; reopen app → hydration +1 and **+250 ml**; Diagnostics shows an `action` run.
- [ ] App **killed** (swipe away): repeat **Done** → same result after reopening.
- [ ] **Done** on a merged reminder completes every routine in it.
- [ ] **Snooze 10m** → the routine shows "Snoozed until HH:MM"; a new reminder arrives ~10 min later; after 3 snoozes in a row the 4th Snooze has no effect.
- [ ] App **in foreground** (iOS especially): tap Done on a banner → recorded exactly once (check counts on Home).

## 4. Tap to open → break screen (Task 7)

- [ ] Tap the notification body with the app in background → Break screen opens for that routine; completing returns to Home with "Quest updated".
- [ ] Same with the app **killed** (cold start) → Break screen opens **once** (no double screen).
- [ ] Merged notification → pages in order Hydration → Stretch → Eye rest with step dots.
- [ ] Eye rest: Start → 20 s countdown, haptic at 0, ring glows, Done highlighted.
- [ ] Hydration: choose 500 ml → Log water → Home shows +500 ml.

## 5. Reliability (Tasks 1, 5) — the gate

- [ ] **Killed for a work day**: arm the schedule, kill the app, leave the phone idle (screen off) ≥ 3 h during work hours. Note fire times vs. Diagnostics plan — all within ~5 min (Android inexact) / on time (iOS).
- [ ] **Reboot** (Android): reboot during work hours, do not open the app → next reminders still arrive.
- [ ] **Reboot** (iOS): reboot → pending reminders still arrive.
- [ ] **App update**: install a new build over the old one without opening it → reminders still arrive (Android `MY_PACKAGE_REPLACED`).
- [ ] **WorkManager** (Android): after ≥ 1 h with the app closed, Diagnostics shows a `periodic` run. Optional: `adb shell dumpsys jobscheduler | grep knight` lists the job.
- [ ] **BGAppRefresh** (iOS, best effort): a `periodic` run appears at some point over a day (iOS decides when; not a failure if rare).
- [ ] **Precision timing** (Android 12+): set `precisionTiming` true via a debug build, allow "Alarms & reminders" → reminders fire on the minute; revoke the permission → falls back to inexact without errors in Diagnostics.
- [ ] **OEM**: on Samsung/Xiaomi with default battery settings note any missed reminders; then disable battery optimization for the app and repeat. (In-app OEM guidance arrives in Milestone 3.)
- [ ] **Force stop** (Android Settings → Force stop): reminders stop (expected); on next launch the schedule is re-armed.

## 6. Time zone and day boundaries (Task 6)

- [ ] Change device time zone (e.g. to Dubai), resume the app → `timezoneChange` run; pending times re-planned to the new local working hours; Home countdowns correct.
- [ ] Change back → another `timezoneChange` run.
- [ ] Leave the app open across 17:00 → Home switches to "Off duty — back on duty Sun 09:00" (on Thursday) without restarting.
- [ ] Friday/Saturday: no reminders at all.

## Report back

For any failure send: device + OS, section/step, expected vs. actual, a screenshot of Diagnostics (Status, Pending, last runs), and `flutter logs` output around the time if available.
