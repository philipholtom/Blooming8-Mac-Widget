#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Blooming8Widget"
BUILD_CONFIG="release"

swift build -c "$BUILD_CONFIG"

BIN_PATH=".build/$BUILD_CONFIG/$APP_NAME"
APP_BUNDLE="$APP_NAME.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "Built $APP_BUNDLE"

INSTALLED="/Applications/$APP_NAME.app"
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1
rm -rf "$INSTALLED"
cp -R "$APP_BUNDLE" "$INSTALLED"
echo "Installed to $INSTALLED"
open "$INSTALLED"
