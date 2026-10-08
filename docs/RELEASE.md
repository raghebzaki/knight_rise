# Knight Rise — Release guide

Everything needed to produce store builds. Items marked **YOU** need your
credentials or artwork; everything else is already in the repository.

## Checklist

| # | Item | Where | Status |
| --- | --- | --- | --- |
| 1 | Android upload keystore | `keys/knight-rise-upload.jks` (git-ignored) | **YOU** |
| 2 | Android signing config | `android/key.properties` from `android/key.properties.example` (git-ignored) | **YOU** |
| 3 | Play App Signing enrolment | Play Console › Setup › App signing | **YOU** |
| 4 | iOS team and bundle id | Xcode › Runner › Signing & Capabilities (bundle id `com.ragheb.knightRise`) | **YOU** |
| 5 | Icon and splash artwork | `assets/branding/` (generated from the logo; final vector from the designer recommended) | Done |
| 6 | Privacy policy values | `site/privacy/index.html` (`{{CONTACT_EMAIL}}`, `{{GITHUB_USER}}`) | **YOU** |
| 7 | GitHub Pages | Repo › Settings › Pages › Source: **GitHub Actions** | **YOU** |
| 8 | Store copy and screenshots | `docs/STORE_LISTING.md` | Draft ready, screenshots **YOU** |
| 9 | Flavors, R8 rules, privacy manifest, BGTask ids | Repository | Done |

## Flavors

| | dev | prod |
| --- | --- | --- |
| Android id | `com.ragheb.knight_rise.dev` | `com.ragheb.knight_rise` |
| Name | Knight Rise Dev | Knight Rise |
| Icon | Amber background | Midnight background |
| Widget gallery, diagnostics, BLoC log | Yes | Removed from the binary |

The Dart flavor is a compile-time constant (`lib/core/config/flavor.dart`):
an explicit `--dart-define=FLAVOR=…` wins, then `--flavor`, and with neither,
**release builds are prod** and debug/profile builds are dev. A forgotten flag
can therefore never ship dev tools.

```sh
flutter run --flavor dev                                  # daily development (Android)
flutter build appbundle --flavor prod --release           # Play upload (.aab)
flutter build apk --flavor prod --release                 # sideload / QA
flutter build ipa --release                               # App Store (prod by default)
flutter run --release --dart-define=FLAVOR=dev            # iOS dev-flavor release run
```

iOS has a single native configuration (bundle `com.ragheb.knightRise`); the
Dart flavor still follows the rules above. A side-by-side iOS dev app needs
Xcode schemes — optional, see "iOS dev scheme" at the end.

## 1–3. Android signing

```sh
mkdir -p keys
keytool -genkeypair -v -keystore keys/knight-rise-upload.jks \
  -alias upload -keyalg RSA -keysize 4096 -validity 10000
cp android/key.properties.example android/key.properties   # then fill in the passwords
```

`storeFile` in `key.properties` is relative to `android/app/`. Without
`key.properties` the build still works but signs release builds with the
debug key and prints a warning; Play rejects such uploads.

Upload the first `.aab` with **Play App Signing** on (Google keeps the app
signing key; `keys/knight-rise-upload.jks` is only the upload key). Back the
keystore and passwords up outside the repository: a lost upload key needs a
Play support reset.

## 4. iOS signing

1. Open `ios/Runner.xcworkspace` in Xcode › Runner target › Signing & Capabilities.
2. Team: your Apple Developer team. Bundle identifier: `com.ragheb.knightRise`
   (change it here if you prefer another; the BGTask identifier
   `com.ragheb.knightRise.reconcile` in `Info.plist` and `AppDelegate.swift`
   does not need to match the bundle id).
3. Capabilities already configured: Background Modes › Background fetch
   (`UIBackgroundModes: fetch`), `BGTaskSchedulerPermittedIdentifiers`.
4. Create the app in App Store Connect with the same bundle id, then
   `flutter build ipa --release` and upload with Transporter or Xcode.

The app target ships `ios/Runner/PrivacyInfo.xcprivacy`: no tracking, no
collected data, file-timestamp API reason `C617.1` (SQLite). Plugins bundle
their own manifests (UserDefaults in flutter_local_notifications and
workmanager_apple).

v1.0 is **iPhone-only** (`TARGETED_DEVICE_FAMILY = 1`), so App Store Connect
needs iPhone screenshots only. iPads can still run it in iPhone compatibility
mode. Adding iPad later means setting the family to `1,2`, restoring the iPad
orientations in `Info.plist` and adding iPad screenshots.

## 5. Icons and splash (done — regenerate when the artwork changes)

Generated from `assets/branding/knight_rise_logo.jpeg` (see
`assets/branding/README.md`). To regenerate:

```sh
/tmp/kr-venv/bin/python -I tool/branding/generate_branding.py   # venv setup in the script header
dart run flutter_launcher_icons
git checkout ios/Runner.xcodeproj/project.pbxproj   # the tool sets an unrelated build setting to an invalid value
dart run flutter_native_splash:create
git checkout ios/Runner/Info.plist                  # the tool only re-indents it
flutter test --tags golden --update-goldens          # refresh the splash goldens
```

Then check: `values*/styles.xml` keep `NormalTheme`'s `windowBackground` at
`@color/splash_background` (`#0A0F1D`, no white flash), and
`mipmap-anydpi-v26/ic_launcher.xml` uses `android:inset="0%"`. The dev flavor
keeps its amber icon background through `android/app/src/dev/res/values/colors.xml`.

The notification small icon (`ic_stat_knight`) is separate: a white
silhouette vector; replace its path data if the mark changes.

## 6–7. Privacy policy on GitHub Pages

The policy lives in `site/` (only that folder is published, not `docs/`).

1. In `site/privacy/index.html`, replace `{{CONTACT_EMAIL}}` and
   `{{GITHUB_USER}}`.
2. Repo › Settings › Pages › Build and deployment › Source: **GitHub Actions**.
3. Push to `main`; `.github/workflows/pages.yml` publishes `site/`.
4. The policy URL is `https://{{GITHUB_USER}}.github.io/knight_rise/privacy/`
   — use it in both store listings and in `docs/STORE_LISTING.md`.

GitHub Pages on a private repository needs a paid plan; the published page is
public either way.

## R8 / resource shrinking (already configured)

`android/app/proguard-rules.pro` keeps `com.dexterous.flutterlocalnotifications.**`
so notifications stored by one release are still readable by the next (the
boot / package-replaced receiver re-schedules them after an update), plus Gson
generics and WorkManager workers. `res/raw/keep.xml` keeps `ic_stat_knight`,
which Dart references by name. Verified on a `--flavor prod --release` build:
plugin model fields keep their names and the drawables survive shrinking.

**Release QA must include an update install** (see `docs/QA_MILESTONE_4.md`):
install build N, let reminders schedule, install build N+1 over it, reboot,
and confirm reminders still fire.

## Versioning

`pubspec.yaml` `version: 1.0.0+1` → bump the build number (`+N`) for every
upload, and keep `kAppVersion` in `lib/core/config/app_info.dart` in sync with
the name part. Android `versionCode` = build number; dev adds `-dev` to the
version name.

## Play Console declarations

- **Data safety:** no data collected or shared (answers in `docs/STORE_LISTING.md`).
- **Exact alarms:** the app declares `SCHEDULE_EXACT_ALARM` (not
  `USE_EXACT_ALARM`) for the opt-in Precision Timing toggle. If Play Console
  asks for an exact-alarm declaration, use the justification in
  `docs/STORE_LISTING.md`.
- **Notifications:** runtime permission (Android 13+), requested only from the
  in-app "Enable reminders" card / onboarding.

## iOS dev scheme (optional)

To install a dev build next to prod on iOS:

1. Xcode › Project › Info › Configurations: duplicate Debug, Release and
   Profile as `Debug-dev`, `Release-dev`, `Profile-dev`, and rename the
   originals `Debug-prod`, `Release-prod`, `Profile-prod`.
2. Manage Schemes: duplicate `Runner` as `dev` and `prod`; point each
   scheme's actions at its configurations.
3. Runner target › Build Settings: for the `-dev` configurations set
   `PRODUCT_BUNDLE_IDENTIFIER = com.ragheb.knightRise.dev` and add a user
   setting `APP_DISPLAY_NAME = Knight Rise Dev` (prod: `Knight Rise`); in
   `Info.plist` set `CFBundleDisplayName` to `$(APP_DISPLAY_NAME)`.
4. `flutter run --flavor dev` then works on iOS too, and the Dart flavor
   follows automatically.
