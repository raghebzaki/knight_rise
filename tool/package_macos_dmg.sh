#!/usr/bin/env bash
# Packages the Release macOS build into a drag-to-install DMG: "Knight Rise.app" next to an /Applications link, on a
# volume named "Knight Rise". Uses hdiutil only (no create-dmg).
#
#   bash tool/package_macos_dmg.sh [--out path/to/file.dmg] [--no-layout] [path/to/knight_rise.app]
#
# Run tool/build_macos_release.sh first. The default output is build/dist/Knight_Rise_v<version>.dmg, with the version
# read from the built app. --no-layout skips the Finder window layout (icon positions, 128 px icons, no toolbar):
# it needs a logged-in Finder and Automation permission, so CI passes it and gets Finder's default icon view instead.
# The .app keeps its ad-hoc signature; Developer ID signing and notarization are manual (docs/RELEASE.md > Desktop).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

APP="build/macos/Build/Products/Release/knight_rise.app"
OUT=""
LAYOUT=1
while (($#)); do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --no-layout) LAYOUT=0; shift ;;
    *) APP="$1"; shift ;;
  esac
done

VOLUME="Knight Rise"
NAME="Knight Rise.app"

if [[ ! -d "$APP" ]]; then
  echo "$APP not found (run tool/build_macos_release.sh first)" >&2
  exit 1
fi
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="${OUT:-build/dist/Knight_Rise_v${version}.dmg}"
mkdir -p "$(dirname "$OUT")"

work="$(mktemp -d)"
trap 'hdiutil detach "/Volumes/$VOLUME" -quiet -force 2>/dev/null || true; rm -rf "$work"' EXIT

# Renaming the bundle folder leaves the executable and the signature untouched; the check below proves it.
mkdir "$work/stage"
ditto "$APP" "$work/stage/$NAME"
ln -s /Applications "$work/stage/Applications"
codesign --verify --deep --strict "$work/stage/$NAME"

hdiutil create -quiet -volname "$VOLUME" -srcfolder "$work/stage" -fs HFS+ -format UDRW -ov "$work/rw.dmg"

if ((LAYOUT)); then
  # A volume left mounted by an earlier run would make the new one mount as "Knight Rise 1".
  hdiutil detach "/Volumes/$VOLUME" -quiet -force 2>/dev/null || true
  hdiutil attach -quiet -readwrite -noverify -noautoopen "$work/rw.dmg"
  osascript <<APPLESCRIPT || echo "Finder layout skipped (no Automation permission for Finder)" >&2
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 760, 460}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set position of item "$NAME" of container window to {140, 160}
    set position of item "Applications" of container window to {420, 160}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
  sync
  hdiutil detach "/Volumes/$VOLUME" -quiet || hdiutil detach "/Volumes/$VOLUME" -quiet -force
fi

rm -f "$OUT"
hdiutil convert -quiet "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"
hdiutil verify -quiet "$OUT"
printf 'Packaged %s (%s)\n' "$OUT" "$(du -h "$OUT" | cut -f1)"
