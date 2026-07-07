#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Blooming8Widget"
BUILD_CONFIG="release"

swift build -c "$BUILD_CONFIG"

BIN_PATH=".build/$BUILD_CONFIG/$APP_NAME"
APP_BUNDLE="$APP_NAME.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "Built $APP_BUNDLE"
echo "Move it to /Applications and double-click to launch, or run: open $APP_BUNDLE"
