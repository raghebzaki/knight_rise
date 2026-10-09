#!/usr/bin/env bash
# Builds the prod macOS release and verifies it (tool/verify_macos_release.sh).
#
#   bash tool/build_macos_release.sh
#
# The result is unsigned for distribution: Developer ID signing and notarization are manual steps, see
# docs/RELEASE.md > Desktop. Release builds are prod anyway (lib/core/config/flavor.dart); the define makes it explicit.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

flutter build macos --release --dart-define=FLAVOR=prod
bash tool/verify_macos_release.sh
