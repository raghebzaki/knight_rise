#!/usr/bin/env bash
# Builds the prod macOS release and verifies it (tool/verify_macos_release.sh).
#
#   bash tool/build_macos_release.sh [--build-name 1.2.0] [--build-number 7]
#
# Extra arguments go to `flutter build macos` (the release workflow passes its version inputs this way); without them
# the version comes from pubspec.yaml. Package a DMG afterwards with tool/package_macos_dmg.sh.
#
# The result is unsigned for distribution: Developer ID signing and notarization are manual steps, see
# docs/RELEASE.md > Desktop. Release builds are prod anyway (lib/core/config/flavor.dart); the define makes it explicit.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

flutter build macos --release --dart-define=FLAVOR=prod "$@"
bash tool/verify_macos_release.sh
