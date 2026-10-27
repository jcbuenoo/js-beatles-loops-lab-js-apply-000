#!/bin/bash
# Builds Pause.app from source. Needs macOS 13+ and Xcode or the Xcode Command Line Tools.
#
#   ./build.sh            build into ./build/Pause.app
#   ./build.sh --install  also copy it to /Applications and open it
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swift >/dev/null; then
    echo "Swift not found. Install the Command Line Tools first:  xcode-select --install" >&2
    exit 1
fi

# UNIVERSAL=1 builds one app that runs on both Apple Silicon and Intel Macs (needs full Xcode).
BUILD_ARGS=(-c release)
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

echo "Building…"
swift build "${BUILD_ARGS[@]}" --product Pause
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

APP="build/Pause.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Pause" "$APP/Contents/MacOS/Pause"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: enough to run on your own Mac. Not for distributing to others.
codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"

if [[ "${1:-}" == "--install" ]]; then
    osascript -e 'tell application id "local.pause.focus" to quit' >/dev/null 2>&1 || true
    sleep 1
    rm -rf "/Applications/Pause.app"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/Pause.app"
    open "/Applications/Pause.app"
fi
