#!/usr/bin/env bash
# Verifies a Release macOS build of Knight Rise and zips it for distribution.
#
#   bash tool/verify_macos_release.sh [path/to/knight_rise.app]
#
# Run `flutter build macos --release` first (tool/build_macos_release.sh does both). Prints PASS/FAIL per check and
# exits non-zero if any fails; the zip is written to build/dist/ only when every check passes. Works with the ad-hoc
# signature of an unsigned CI build: the entitlements are embedded either way.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

APP="${1:-build/macos/Build/Products/Release/knight_rise.app}"
EXPECTED_BUNDLE_ID="com.ragheb.knightRise"
EXPECTED_DISPLAY_NAME="Knight Rise"
EXPECTED_MIN_OS="13.0"

failures=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
check() { # check <description> <command...>
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then pass "$description"; else fail "$description"; fi
}

if [[ ! -d "$APP" ]]; then
  printf 'FAIL  %s not found (run flutter build macos --release first)\n' "$APP"
  exit 1
fi

PLIST="$APP/Contents/Info.plist"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }

# --- Entitlements -----------------------------------------------------------------------------------------------
# The app is offline: sandbox on, no JIT (release is AOT), no network client or server. If a plugin ever needs one
# of these, add it to macos/Runner/Release.entitlements deliberately and update this list with the reason.
entitlements="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
if grep -q 'com.apple.security.app-sandbox' <<<"$entitlements" &&
  tr -d '[:space:]' <<<"$entitlements" | grep -q 'com.apple.security.app-sandbox</key><true/>'; then
  pass "entitlements: app-sandbox is true"
else
  fail "entitlements: app-sandbox is true"
fi
for forbidden in com.apple.security.cs.allow-jit com.apple.security.network.server com.apple.security.network.client; do
  if grep -q "$forbidden" <<<"$entitlements"; then
    fail "entitlements: no $forbidden"
  else
    pass "entitlements: no $forbidden"
  fi
done

# --- Info.plist -------------------------------------------------------------------------------------------------
[[ "$(plist LSMinimumSystemVersion)" == "$EXPECTED_MIN_OS" ]] &&
  pass "Info.plist: LSMinimumSystemVersion is $EXPECTED_MIN_OS" ||
  fail "Info.plist: LSMinimumSystemVersion is $EXPECTED_MIN_OS (got '$(plist LSMinimumSystemVersion)')"
[[ "$(plist CFBundleIdentifier)" == "$EXPECTED_BUNDLE_ID" ]] &&
  pass "Info.plist: CFBundleIdentifier is $EXPECTED_BUNDLE_ID" ||
  fail "Info.plist: CFBundleIdentifier is $EXPECTED_BUNDLE_ID (got '$(plist CFBundleIdentifier)')"
[[ "$(plist CFBundleDisplayName)" == "$EXPECTED_DISPLAY_NAME" ]] &&
  pass "Info.plist: CFBundleDisplayName is $EXPECTED_DISPLAY_NAME" ||
  fail "Info.plist: CFBundleDisplayName is $EXPECTED_DISPLAY_NAME (got '$(plist CFBundleDisplayName)')"

# --- Bundled resources ------------------------------------------------------------------------------------------
ASSETS="$APP/Contents/Frameworks/App.framework/Resources/flutter_assets"
check "tray icon asset is bundled" test -f "$ASSETS/assets/branding/tray/tray_icon_template.png"
check "Orbitron/Rajdhani/Inter fonts are bundled" test -f "$ASSETS/assets/fonts/Orbitron-Variable.ttf" -a -f "$ASSETS/assets/fonts/Inter-Variable.ttf"

# Flutter compiles the ARB files into the AOT snapshot, so look for one known string per language in the binary
# (English is Latin-1, Arabic is UTF-16 in the Dart heap). BSD `strings` cannot scan UTF-16, hence python3.
AOT="$APP/Contents/Frameworks/App.framework/Versions/A/App"
[[ -f "$AOT" ]] || AOT="$APP/Contents/Frameworks/App.framework/App"
has_string() { # has_string <encoding> <text>
  python3 -c 'import sys; sys.exit(0 if sys.argv[2].encode(sys.argv[1]) in open(sys.argv[3], "rb").read() else 1)' \
    "$1" "$2" "$AOT"
}
if has_string latin-1 'Start Knight Rise when you sign in'; then
  pass "English localization is compiled in"
else
  fail "English localization is compiled in"
fi
if has_string utf-16-le 'التشغيل عند تسجيل الدخول'; then
  pass "Arabic localization is compiled in"
else
  fail "Arabic localization is compiled in"
fi

# --- Result -----------------------------------------------------------------------------------------------------
if ((failures > 0)); then
  printf '\n%d check(s) failed; not packaging.\n' "$failures"
  exit 1
fi

# The built version, so a `--build-name` override (the release workflow) names the zip correctly.
version="$(plist CFBundleShortVersionString)"
mkdir -p build/dist
zip_path="build/dist/knight_rise-macos-${version}.zip"
rm -f "$zip_path"
ditto -c -k --keepParent "$APP" "$zip_path"
printf '\nAll checks passed. Packaged %s\n' "$zip_path"
