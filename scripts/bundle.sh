#!/bin/sh
# Assemble build/Aeris.app from the SwiftPM binary. Usage: scripts/bundle.sh [debug]
set -eu
cd "$(dirname "$0")/.."

CONFIG=release
[ "${1:-}" = "debug" ] && CONFIG=debug

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/AerisEditor"

APP=build/Aeris.app
# Never replace the bundle under a running copy: macOS then refuses it system services (e.g. the save
# panel fails to connect). Self-check runs don't count. AERIS_FORCE_BUNDLE=1 overrides.
if [ -z "${AERIS_FORCE_BUNDLE:-}" ] && ps -ax -o command= | grep -v -- '--selfcheck' | grep -qF "$(pwd)/$APP/Contents/MacOS/AerisEditor"; then
  echo "bundle.sh: $(pwd)/$APP is running - quit it first (or AERIS_FORCE_BUNDLE=1). Nothing replaced." >&2
  exit 3
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AerisEditor"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"
echo "$(pwd)/$APP"
