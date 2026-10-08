# Knight Rise

**Stay Active. Stay Focused.**

Knight Rise is an offline-first Flutter app (Android and iOS) for desk workers. It schedules hydration, quick-stretch and eye-rest reminders inside your working hours, lets you act on them straight from the notification, and tracks daily progress as a "Quest Log". Timing is owned by the OS notification scheduler rather than in-app timers, so reminders survive the app being backgrounded or killed.

Design, architecture and roadmap: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Getting started

Requirements: Flutter 3.47.x (Dart 3.13).

```bash
flutter pub get

# Code generation: *.g.dart, *.freezed.dart, injection.config.dart
dart run build_runner build

# Localization (lib/l10n/arb -> lib/l10n/generated)
flutter gen-l10n

# Android has native flavors: always pass one (plain `flutter run` fails
# with "Gradle build failed to produce an .apk file").
flutter run --flavor dev               # Android, dev (Knight Rise Dev, .dev id)
flutter run --flavor prod              # Android, prod
flutter run --dart-define=FLAVOR=dev   # iOS (single Xcode configuration)
```

IDE: pick a shared run configuration — Android Studio `.run/` or VS Code
`.vscode/launch.json`: **Knight Rise (Android dev)**, **(Android prod)** or
**(iOS)**. Release builds and flavors: `docs/RELEASE.md`.

## Project structure

```text
lib/
  main.dart, app.dart
  core/
    clock/       Clock abstraction
    config/      Build flavor (dev/prod)
    database/    Drift database
    di/          get_it + injectable setup
    router/      go_router configuration
    theme/       Palette, tokens, theme, KnightCard, KnightRing
    time/        Local-day helpers, timezone loader
    utils/       Shared helpers (combine_latest)
  features/
    cycle/          CycleBloc, home page, break page, Shield section
    device_health/  Permission/battery status, OEM guides (native channel)
    diagnostics/    Debug screen: pending notifications, reconcile runs
    gallery/        Widget gallery page
    notifications/  NotificationGateway, channels, actions, payloads
    onboarding/     Onboarding gate and four-step flow
    routines/       Routine entity, repository, list and editor pages
    scheduler/      ReminderPlanner, ReconcileSchedule, sync service, background tasks
    settings/       App settings, ThemeCubit, settings hub
    shield/         Shield sessions, use cases, cubit
    work_hours/     Work schedule, day overrides, editor page
  l10n/          ARB sources and generated localizations
```

Features follow a domain / data / presentation split, and domain code stays free of Flutter imports.

## Testing

```bash
flutter test      # unit, widget and gate suites (what CI runs)
flutter analyze
```

Suites:

- Unit: `ReminderPlanner`, `ReconcileSchedule`, Shield and day-override use cases, Drift repositories and migrations, cubits and blocs
- Widget: home, break, settings, work hours, routine editor, device health, onboarding, diagnostics
- Gate (`test/gate/`): end-to-end scenarios below the UI with a real in-memory database and an OS-faithful notification simulator, asserting exact pending schedules for Shield start/extend/end, work-hours edits and day overrides

On-device integration test (not run in CI). It compares the real OS pending notifications with the planner and exercises a Shield. Use a connected phone or emulator, grant notification permission, and run it during work hours (otherwise it skips):

```bash
flutter test integration_test/notification_schedule_test.dart -d <device>
```

## Roadmap

- Milestone 1, core theme and timer MVP: done
- Milestone 2, background scheduling and interactive notifications: done
- Milestone 3, Shield Mode and settings customization: done
- Milestone 4, Quest Log dashboard, history and polish: pending

## Fonts

Orbitron, Rajdhani and Inter are bundled under `assets/fonts/` so the app works offline. Their SIL Open Font License texts are included alongside the font files.
