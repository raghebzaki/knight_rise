# Knight Rise — Architecture & Roadmap

*Stay Active. Stay Focused.*

_Status: Approved · Oct 5, 2026_

## Overview

Knight Rise is an offline-first Flutter app (Android + iOS) that schedules hydration, stretch and eye-rest reminders inside the user's working hours, lets them act on reminders straight from the notification, and tracks daily progress as a "Quest Log". The central design decision: **the OS notification scheduler is the source of truth for timing, not an in-app Dart timer.** Dart timers die when the app is backgrounded or killed; pre-scheduled OS notifications survive.

| Decision | Choice | Why |
| --- | --- | --- |
| Targets | Android 8+ (API 26), iOS 15+ | Covers notification channels and modern iOS notification actions |
| State management | flutter\_bloc (Cubit for simple state, Bloc for event-heavy flows) | Testable, explicit transitions, fits clean architecture |
| Scheduling | flutter\_local\_notifications zonedSchedule as primary; workmanager as a re-arm safety net | Only OS-level scheduling survives app death on both platforms |
| Persistence | Drift (SQLite) — see Persistence | Safe multi-isolate writes, relational queries for aggregates |
| DI | get\_it + injectable | Compile-time wiring, easy test overrides |
| Navigation | go\_router | Deep links from notification taps into specific screens |
| Immutability | freezed + json\_serializable | Value equality for BLoC states and entities |

Out of scope for v1: accounts, cloud sync, wearables, calendar integration (noted as a later Shield Mode enhancement).

## 1. Design system & theme engine

Tokens live in one `KnightTokens` ThemeExtension plus a Material 3 `ColorScheme`, so every widget reads from the theme and Dark/AMOLED is a single swap. Cyan is reserved for energy and action (primary buttons, active rings, focus); everything else stays navy, steel and silver so the accent keeps its punch.

### Color tokens

| Token | Dark (Midnight) | AMOLED | Use |
| --- | --- | --- | --- |
| `primary` | #00E5FF | #00E5FF | Electric cyan: CTAs, active ring, focus |
| `onPrimary` | #00212A | #00212A | Text/icons on cyan |
| `secondary` | #2F80FF | #2F80FF | Neon energy blue: gradient end, links |
| `background` | #0A1020 | #000000 | Scaffold |
| `surface` | #111A2E | #05080F | Cards, sheets |
| `surfaceContainerHigh` | #1A2540 | #0C1322 | Elevated cards, ring track |
| `outline` (steel) | #34445F | #263248 | Card borders, dividers |
| `outlineStrong` (silver) | #5B6B87 | #475570 | Focused/selected borders |
| `onSurface` | #E6EDF5 | #E6EDF5 | Silver-white primary text |
| `onSurfaceVariant` | #A7B4C8 | #9AA7BC | Brushed-steel secondary text |
| `textMuted` | #6F7E96 | #64738A | Captions, disabled |
| `glow` | #00E5FF @ 30% | #00E5FF @ 40% | Glow shadows on active cards |
| `success` | #2EE6A6 | #2EE6A6 | Quest complete |
| `warning` | #FFB547 | #FFB547 | Snoozed / overdue |
| `error` | #FF5C7A | #FF5C7A | Errors, permission missing |
| `routine.hydration` | #00E5FF | #00E5FF | Water ring + icon |
| `routine.stretch` | #2EE6A6 | #2EE6A6 | Stretch ring + icon |
| `routine.eyeRest` | #8FA8FF | #8FA8FF | Eye-rest ring + icon |

AMOLED drops surfaces to near-black and leans on borders, not fills, for separation. All text pairs above meet WCAG AA (4.5:1) on their backgrounds; verify with a contrast test in Milestone 1.

### Typography

Bundle fonts as assets (no runtime fetch) so the app works offline.

| Role | Font | Size / line height | Weight | Notes |
| --- | --- | --- | --- | --- |
| displayLarge (timer, ring center) | Orbitron | 48 / 56 | 600 | Tabular figures; numbers only |
| headlineMedium (screen titles) | Rajdhani | 28 / 34 | 700 | Uppercase, +0.5 letter spacing |
| titleLarge (card titles) | Rajdhani | 20 / 26 | 600 |  |
| titleMedium | Inter | 16 / 22 | 600 |  |
| bodyLarge | Inter | 16 / 24 | 400 |  |
| bodyMedium | Inter | 14 / 20 | 400 |  |
| labelLarge (buttons) | Inter | 14 / 20 | 600 | +0.4 letter spacing |
| labelSmall (chips, captions) | Inter | 11 / 16 | 500 |  |

Respect system text scaling up to 1.3×; the timer display clamps so ring layouts don't break.

### Shape, spacing, elevation

- Spacing: 4-pt grid (`xs 4, sm 8, md 12, lg 16, xl 24, xxl 32`).
- Radius: `sm 6` (chips), `md 12` (buttons, inputs), `lg 16` (cards). Hero cards use a `BeveledRectangleBorder` with 12 px chamfered corners: the cyber-knight "armor plate" motif.
- Elevation is replaced by borders and glow: cards are flat `surface` with a 1 px `outline` border; the active/next-due card gets a 1.5 px `primary` border plus `BoxShadow(glow, blur 16, spread 0)`.

### Component theming

- **FilledButton (primary):** cyan fill, `onPrimary` label, 48 px min height, `md` radius; pressed state darkens to #00B8D4 and adds glow.
- **OutlinedButton (secondary):** transparent, 1 px `outlineStrong` border, silver label; hover/focus border becomes cyan.
- **TextButton:** cyan label, used for "Snooze" and tertiary actions.
- **Card (`KnightCard` widget):** surface fill, steel border, optional `glow: true`, optional chamfer; padding `lg`.
- **Switch / Slider / Chip:** active track cyan at 40%, thumb cyan; inactive in steel.
- **NavigationBar:** background `surface`, cyan indicator pill at 16% opacity, silver icons.
- **SnackBar / Dialog:** `surfaceContainerHigh` with steel border, no Material elevation tint (`surfaceTintColor: transparent`).

### Progress rings

A custom `KnightRing` (CustomPainter, not a package) draws three concentric rings, outer to inner: hydration, stretch, eye rest. Spec: 10 px stroke, 6 px gap, round caps, track in `surfaceContainerHigh`, progress as a sweep gradient from the routine color to `secondary`. Progress animates with a 600 ms ease-out. At 100% the ring pulses once and gains a soft glow; the center shows the overall quest percentage in Orbitron. A compact single-ring variant is used on routine cards.

### Theme engine & Dark/AMOLED

- `KnightTheme.build(KnightPalette palette)` returns `ThemeData` from one palette object; `KnightPalette.midnight` and `KnightPalette.amoled` are the two presets.
- `ThemeCubit` holds `ThemeVariant { midnight, amoled }` (v1 ships these two only; no light theme), persisted in settings.
- Widgets read brand-only values with `context.knight` (an extension over `Theme.of(context).extension<KnightTokens>()`); no hex literals outside `core/theme/`.
- `SystemUiOverlayStyle` updates status/nav bar colors with each variant so AMOLED gets a true-black nav bar.

```dart
@immutable
class KnightTokens extends ThemeExtension<KnightTokens> {
  final Color glow, success, warning, outlineStrong, textMuted;
  final Color hydration, stretch, eyeRest;
  final List<BoxShadow> activeGlow;
  final double chamfer;
  // copyWith / lerp generated or hand-written
}
```

## 2. Architecture & state management

Feature-first clean architecture with one rule that shapes everything: **use cases are the shared surface between the UI and the background isolates.** Notification action handlers and WorkManager callbacks run in a separate isolate with no widget tree and no BLoCs, so they call the same domain use cases through a lightweight DI bootstrap.

### Layers

- **Domain (pure Dart, no Flutter imports):** entities, repository interfaces, use cases, and the `ReminderPlanner` — a pure function that takes routines, working hours, Shield windows, snoozes and `now`, and returns the next N fire times. Pure logic means it is fully unit-testable with a fake clock.
- **Data:** Drift tables, DAOs + mappers, `NotificationGateway` (wraps flutter\_local\_notifications), `BackgroundTaskGateway` (wraps workmanager), `DeviceHealthGateway` (battery-optimization and exact-alarm status via platform channel / permission\_handler), repository implementations.
- **Presentation:** pages, widgets, BLoCs/Cubits. Depends on Domain only; never imports Data.
- **Core:** theme, router, DI, `Clock` abstraction, logger, error types (`Either<Failure, T>` via fpdart).

### Folder structure

```text
lib/
  main.dart                      # UI entry: bootstrap() + runApp
  background_main.dart           # @pragma('vm:entry-point') handlers
  core/
    theme/ (palette, knight_theme, tokens, widgets/knight_card, knight_ring)
    di/ (injection.dart, bootstrap_background.dart)
    router/  clock/  utils/  error/
  features/
    routines/      {domain, data, presentation}   # intervals, enable/disable
    scheduler/     {domain, data}                 # ReminderPlanner, notification + WM gateways
    shield/        {domain, data, presentation}   # focus/meeting mode
    quest_log/     {domain, data, presentation}   # daily dashboard, history
    work_hours/    {domain, data, presentation}
    settings/      {domain, data, presentation}   # theme, sounds, permissions health
    onboarding/    {presentation}                 # permission walkthrough
```

### Core domain entities

| Entity | Key fields |
| --- | --- |
| `Routine` | id, type (hydration / stretch / eyeRest / custom), intervalMinutes, enabled, dailyTarget, soundId, vibrate |
| `WorkSchedule` | per-weekday list of `TimeWindow(start, end)`, timezone id, lunchBreak? |
| `ShieldSession` | id, startAt, endAt, reason (focus / meeting / manual), source |
| `ReminderEvent` | id, routineId, scheduledAt, firedAt?, outcome (done / snoozed / missed / dismissed), resolvedAt?, snoozeCount |
| `DailyQuest` | date, per-routine completed vs target, waterMl, streakDay |

### BLoCs and Cubits

BLoCs never talk to each other; they react to repository streams (Drift `watch()`), which also picks up writes made by the background isolate.

| BLoC / Cubit | Owns | Main events / methods |
| --- | --- | --- |
| `CycleBloc` (core engine) | Per-routine status: offHours, active(nextDueAt), due, snoozed(until), shielded(until) | AppResumed, ConfigChanged, ReminderResolved, DayRolledOver, TickRequested |
| `QuestLogCubit` | Today's progress, streak, 7-day history | load(date), watches ReminderEvent stream |
| `ShieldCubit` | Active Shield session + countdown | activate(duration, reason), extend(), end() |
| `RoutinesCubit` | Routine list editing | toggle, updateInterval, updateTarget |
| `WorkHoursCubit` | Weekly schedule editor | setWindow(day, window), copyToWeekdays() |
| `SettingsCubit` / `ThemeCubit` | Theme variant, sounds, haptics | setVariant, setSound |
| `DeviceHealthCubit` | Notification / exact-alarm / battery-optimization status | refresh() on resume |

**Timers:** countdowns are derived, never stored. `CycleBloc` keeps `nextDueAt` (persisted); the UI's 1-second ticker is a `Stream.periodic` that only re-renders `nextDueAt - clock.now()` while the screen is visible, cancelled on pause. Killing the app loses nothing because the truth lives in Drift and in the OS schedule.

**Every config change flows the same way:** Cubit → use case writes config → `RescheduleAll` use case → `ReminderPlanner` computes the next window → `NotificationGateway` cancels and re-registers → streams update the UI.

## 3. Background processing & reliability

Strategy: **pre-schedule a rolling window of OS notifications, then reconcile it from every wake-up we can get.** Nothing depends on Dart code running at the moment a reminder fires, which is the only approach that works on both platforms.

### The rolling window

- `ReminderPlanner` expands each enabled routine across working hours, skipping Shield windows and applying snoozes, and returns the next fire times.
- **iOS caps an app at 64 pending local notifications**, so the window is the next 24 h or 50 notifications, whichever is smaller (headroom for snoozes). Example: hydration every 30 min + stretch every 45 min + eye rest every 20 min over a 9 h day is about 57 per day, so the cap is real.
- Notification IDs are deterministic (`hash(routineId, scheduledAt minute) → int32`), so re-running the planner is idempotent: cancel what's no longer planned, add what's missing, leave the rest.
- Every scheduled notification also gets a `ReminderEvent` row (status `scheduled`) so actions and history map back to it.

### Reconcile triggers

`ReconcileSchedule` (top up the window, mark overdue unresolved events as `missed`, roll the day over) runs on:

1. App launch and every resume.
2. Any config change (routines, work hours, Shield).
3. Every notification action (Done / Snooze), inside the background handler.
4. Device reboot and app update (Android boot receiver).
5. A periodic workmanager task (Android: every 60 min, min allowed 15; iOS: BGAppRefresh, opportunistic).
6. Timezone or clock change detected on resume (compare stored tz id with `flutter_timezone`).

### Android specifics

| Concern | Approach |
| --- | --- |
| Exact vs inexact | Default `AndroidScheduleMode.inexactAllowWhileIdle` (a few minutes of drift, acceptable for wellness nudges, no special permission). Opt-in "Precision Timing" toggle on the Device Health screen requests `SCHEDULE_EXACT_ALARM` and switches to `exactAllowWhileIdle`. Avoid `USE_EXACT_ALARM`: Play restricts it to alarm-clock/calendar apps. |
| Notification permission | Request `POST_NOTIFICATIONS` (Android 13+) during onboarding, after explaining value. |
| Reboot / update | flutter\_local\_notifications' boot receiver (`RECEIVE_BOOT_COMPLETED`) restores its scheduled notifications; workmanager tasks also survive reboot and run a reconcile. |
| Doze / App Standby | `allowWhileIdle` modes fire in Doze maintenance windows; reminders only matter while the user is active, so this is acceptable. |
| OEM killers (Xiaomi, Huawei, Oppo/Realme, OnePlus, Samsung) | `DeviceHealthCubit` detects manufacturer and battery-optimization status; settings screen deep-links to the battery-optimization and auto-start pages with per-OEM instructions. Use `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`, not the direct-request permission, to stay inside Play policy. |
| Force stop | Android cancels all alarms; nothing can fire until the user reopens the app. On next launch, reconcile and show "Reminders were paused" banner. |
| Channels | One channel per routine type (user can mute stretch but keep water) + one low-importance channel for Shield status. |

### iOS specifics

| Concern | Approach |
| --- | --- |
| No background timers | Accepted. All timing via `UNCalendarNotificationTrigger` through zonedSchedule. |
| 64-notification cap | Rolling window above; BGAppRefresh and every app open top it up. If the user never opens the app for 24 h+, reminders stop: show this honestly in Settings ("Open Knight Rise daily to keep your schedule armed"). |
| Reboot | Pending notifications persist across reboot; no action needed. |
| Actions | `DarwinNotificationCategory` with actions; Done and Snooze run without opening the app (background response handler gets a short execution window). |
| Focus modes | Use interruption level `active`. `timeSensitive` needs an entitlement and Apple expects it for urgent alerts only; offer it later if testing shows reminders are getting buried. |

### Background isolate entry point

- Top-level `@pragma('vm:entry-point')` functions for `onDidReceiveBackgroundNotificationResponse` and the workmanager `callbackDispatcher`.
- Each calls `bootstrapBackground()`: `WidgetsFlutterBinding`/`DartPluginRegistrant.ensureInitialized()`, timezone init, open the database, register only data sources + use cases.
- The database must tolerate a second isolate writing concurrently — this is the deciding factor in the Persistence section.

### Rejected alternatives

- **android\_alarm\_manager\_plus:** runs Dart at the alarm, Android-only; unnecessary when notifications are pre-built.
- **Foreground service with a live timer:** most precise, but a permanent notification, Android 14 foreground-service-type review, and battery cost. Revisit only if inexact timing gets real complaints.
- **In-app Dart `Timer` as source of truth:** dies with the process.

## 4. Core features

### 4.1 Routine intervals

| Routine | Default interval | Allowed range | Daily target | Notification copy (example) |
| --- | --- | --- | --- | --- |
| Hydration | 45 min | 15–120 min | 2,000 ml (8 × 250 ml) | "Refuel, Knight. One glass of water." |
| Quick Stretch | 60 min | 30–180 min | 6 breaks | "Rise and stretch: 2 minutes, stand up." |
| Eye Rest (20-20-20) | 20 min | 15–60 min | 12 rests | "Look 20 ft away for 20 seconds." |

- Intervals anchor to the start of the work window (09:00 + 45 min, not "45 min after the app opened"), so the schedule is predictable.
- After a Done, the next reminder for that routine shifts to `doneAt + interval` (rolling), so an early break doesn't produce an immediate second nudge. Make this a per-routine setting: **Rolling** (default) or **Fixed grid**.
- Collision rule: if two routines fall within 5 min of each other, merge into one notification ("Water + stretch") with both Done actions, to avoid spamming.
- Custom routines (name, icon, interval) are modeled in v1 but exposed in the UI after launch.

### 4.2 Interactive notifications

| Action | Behavior | Opens app? |
| --- | --- | --- |
| **Done / Claim Break** | Marks event `done`, increments quest progress, reschedules that routine from now | No |
| **Snooze 10m** | Marks `snoozed`, schedules a one-off reminder at now + 10 min (max 3 snoozes, then the action is hidden) | No |
| Tap on body | Opens the guided break screen (stretch animation / eye-rest 20 s countdown / water logger) via go\_router deep link | Yes |
| Swipe away | Recorded as `dismissed` on next reconcile; counts as missed, not failed | — |

Hydration's Done logs 250 ml automatically without opening the app; precise amounts are entered in-app. Android gets action buttons and a big-text style; iOS gets the same via a notification category.

### 4.3 Shield Mode (focus / meeting)

- One-tap presets: **25 min**, **50 min**, **Until I turn it off** (auto-expires at end of work day), plus custom.
- Activation cancels notifications inside the window and the planner skips it; ending early triggers a reconcile.
- Optional **"Recover on exit"**: when Shield ends, send a single summary nudge ("Shield down. 2 waters and 1 stretch waiting.") instead of replaying every missed reminder.
- A low-priority ongoing notification on Android shows Shield remaining time with an "End Shield" action; iOS shows status in-app only (a Live Activity is a stretch goal).
- Shield sessions are stored and shown on the dashboard as "Focus time".
- Later: auto-Shield from calendar busy events (device\_calendar) — out of scope for v1.

### 4.4 Daily dashboard / Quest Log

- Hero: the triple `KnightRing` with overall quest % in the center, and today's "next up" card with live countdown and quick Done.
- Routine cards: completed / target, last completion time, mini ring.
- Water logger: tap chips (150 / 250 / 500 ml) with undo.
- Streak: a day counts when every enabled routine reaches at least 70% of its target (configurable); shown as a "Knight rank" (Squire → Knight → Paladin) at 3 / 7 / 30 days.
- History tab: 7- and 30-day bar charts per routine, completion rate, focus minutes.
- Day boundary = local midnight; end-of-day summary notification optional.

### 4.5 Working hours customizer

- Per-weekday on/off with one or more time windows (supports split shifts and a lunch block); "Copy Monday to weekdays".
- Outside working hours the app is dormant: no reminders, dashboard shows "Off duty" with tomorrow's start time.
- Quick overrides: "Working late today (+1 h)", "Day off today".
- Stored with the IANA timezone; schedules are expressed in local wall-clock time and re-planned on timezone change (travel, DST).

## 5. Persistence

**Decision: Drift (SQLite).** Its multi-isolate support (a shared `DriftIsolate` connection discovered through `IsolateNameServer`, with a direct-open fallback) makes concurrent writes from background handlers safe, and SQL gives us reliable relational queries for history and streaks. All access stays behind repository interfaces.

| Criterion | Hive (hive\_ce) | Isar (community fork) | Drift (SQLite) |
| --- | --- | --- | --- |
| Multi-isolate writes | Risky: separate isolates opening the same box can clobber each other | Supported: same instance opened in each isolate | Supported with a shared/isolate-backed connection |
| Queries for history and streaks | Manual, in Dart | Indexed queries, filters, aggregates | Full SQL |
| Reactive streams | Box listen (coarse) | `watch()` per query / object | `watch()` per query |
| Maintenance outlook | Community edition | Community fork | Actively maintained |
| Fit for Knight Rise | Settings only | Good | Good, slightly more boilerplate |

Store settings in the same database (a single `AppSettings` record), not SharedPreferences: SharedPreferences caches per isolate, so a background handler can read stale config.

### Tables

| Collection | Indexes | Retention |
| --- | --- | --- |
| `RoutineModel` | type | Permanent |
| `WorkScheduleModel` | — (single record) | Permanent |
| `ShieldSessionModel` | startAt | 90 days |
| `ReminderEventModel` | (routineId, scheduledAt), status, notificationId | 90 days raw |
| `DailySummaryModel` | date (unique) | Permanent (small; powers streaks and charts) |
| `WaterLogModel` | timestamp | 90 days |
| `AppSettingsModel` | — (single record) | Permanent |

`DailySummaryModel` is updated on every completion and finalized at day rollover, so the dashboard and streak never scan raw events. A schema version number plus migration functions ship from day one.

## 6. Phased roadmap

Four milestones, about 10 weeks for one developer (estimate, assuming full-time). One change from the brief: a minimal Drift setup moves into Milestone 1, because the Milestone 2 background handlers need a database that is safe across isolates. Milestone 4 keeps history, summaries and migrations.

```text
M1 Core theme & timer MVP (~2w)  --[Planner tests pass]-->
M2 Background reliability (~3w)  --[Survives kill + reboot]-->   <- highest risk
M3 Shield & settings (~2w)       --[Shield edge cases pass]-->
M4 Quest Log, history, polish (~3w)
```

Each diamond is a gate: the next milestone starts only once its criterion passes on real devices.

### Milestone 1 — Core theme & MVP timer logic

- [x] Project scaffold: flavors (dev/prod; Dart-define now, native flavors before store builds), lints (very\_good\_analysis), get\_it + injectable, go\_router, CI (format, analyze, test).
- [x] `KnightPalette`, `KnightTokens`, `KnightTheme` (Midnight + AMOLED), bundled fonts, `KnightCard`, `KnightRing`, buttons; a widget gallery screen.
- [x] Domain entities, `Clock` abstraction, `ReminderPlanner` with exhaustive unit tests (work windows, intervals, collisions, DST).
- [x] Drift core: routines, settings, reminder events.
- [x] `CycleBloc` with a foreground-only countdown and in-app "Done".

**Exit:** planner test suite green (including DST and midnight edge cases); themed home screen shows live countdowns for three routines.

### Milestone 2 — Background scheduling & interactive notifications

- [ ] `NotificationGateway`: channels, categories, zonedSchedule, deterministic IDs.
- [ ] Rolling-window `ReconcileSchedule` + all six triggers.
- [ ] Background action handler (Done / Snooze) with `bootstrapBackground()`.
- [ ] workmanager periodic reconcile; Android boot receiver; inexact default + exact opt-in.
- [ ] Deep links from notification tap to guided break screens.

**Exit:** on a Pixel, a Samsung and a Xiaomi device plus an iPhone, reminders fire within 5 min of schedule over a full work day with the app killed, after a reboot, and with Done/Snooze handled without opening the app.

### Milestone 3 — Shield Mode & settings customization

- [ ] Shield presets, ongoing Android notification, "Recover on exit" summary.
- [ ] Work hours editor: per-day windows, split shifts, copy-to-weekdays, today overrides.
- [ ] Routine settings: interval, target, rolling vs fixed, sound, vibration.
- [ ] Device health screen: permission status, battery-optimization and OEM guides.
- [ ] Onboarding flow with permission priming.

**Exit:** Shield start/end/extend, mid-reminder activation, and work-hours edits produce exactly the expected pending notifications (verified by an integration test that inspects the pending list).

### Milestone 4 — Dashboard, persistence, polish

- [ ] Quest Log dashboard, water logger, streak and Knight ranks.
- [ ] `DailySummaryModel`, 7/30-day history charts, 90-day retention job, schema migrations.
- [ ] Polish: micro-animations, haptics, empty/error states, accessibility (screen reader labels on rings, text scale), intl scaffolding only (full Arabic/RTL localization in v1.1).
- [ ] Release: icons, splash, store listings, privacy policy (all data local), Play exact-alarm declaration if the opt-in ships.

**Exit:** a week of internal dogfooding with no missed-schedule bugs; store builds approved.

## 7. Risks, testing & open questions

### Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| OEM battery killers drop scheduled alarms | Reminders silently stop on some Android brands | Device health screen + OEM guides; reconcile on every wake; "reminders paused" banner |
| iOS 64-notification cap + no reopen for 24 h | Schedule runs dry | Rolling window, BGAppRefresh top-up, honest in-app note |
| Exact-alarm policy changes on Play | Rejection or permission loss | Inexact by default; exact is opt-in and degrades gracefully |
| Schema migrations break on update | User history lost | Schema versioning from day one; drift\_dev schema dumps + migration tests |
| Notification fatigue | Users mute the app | Collision merging, Shield, "Recover on exit" summary, per-routine channels |

### Testing strategy

- **Unit:** `ReminderPlanner` (the riskiest logic) with a fake clock: work windows, split shifts, DST jumps, midnight rollover, Shield overlap, snooze caps; use cases with mocked repositories (mocktail).
- **BLoC:** bloc\_test for every state transition in `CycleBloc`, `ShieldCubit`, `QuestLogCubit`.
- **Widget/golden:** golden tests for `KnightCard`, `KnightRing` and key screens in both Midnight and AMOLED, plus 1.3× text scale.
- **Integration:** integration\_test that asserts on `pendingNotificationRequests()` after config changes.
- **Device matrix (manual, each milestone):** Pixel (stock), Samsung (One UI), Xiaomi (HyperOS), iPhone; scenarios: app killed, reboot, Doze overnight, timezone change, force stop.
- **Diagnostics:** an in-app debug screen (dev flavor) listing pending notifications and the last 50 reconcile runs.

### Decisions (approved)

- Persistence: **Drift (SQLite)**.
- Timing: `inexactAllowWhileIdle` by default; opt-in **Precision Timing** toggle on the Device Health screen.
- Theme: **Midnight + AMOLED only** for v1; no light theme.
- Fonts: Orbitron (tabular ring/timer numbers), Rajdhani (titles), Inter (body/UI), bundled as offline assets.
- Water: **ml**, 250 ml per tap; notification Done logs 250 ml automatically.
- Arabic/RTL: intl scaffolding in v1; full localization in v1.1.
