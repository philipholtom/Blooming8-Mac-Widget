#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Blooming8Widget"
BUILD_CONFIG="Release"
XCODE_BETA="/Applications/Xcode-beta.app/Contents/Developer"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/Blooming8_Screen_Widget-bemzrgmnicnbnxfhqswrxccqxuqi"

"$XCODE_BETA/usr/bin/xcodebuild" -scheme "$APP_NAME" -configuration "$BUILD_CONFIG" -destination "generic/platform=macOS" build

BIN_PATH="$DERIVED_DATA/Build/Products/$BUILD_CONFIG/$APP_NAME"
APP_BUNDLE="$APP_NAME.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Codesign the assembled bundle. Without this the only signature is the one the
# linker applied to the bare executable, before Info.plist was copied in — so
# the plist is left unsealed ("Info.plist=not bound"). TCC refuses to trust an
# unsealed NSBluetoothAlwaysUsageDescription and denies Bluetooth outright,
# which surfaces as CBCentralManager reporting .unauthorized and every BLE wake
# failing silently. Ad-hoc is enough to seal it.
codesign --force --sign - --identifier "com.pholtom.blooming8widget" "$APP_BUNDLE"
codesign -dv "$APP_BUNDLE" 2>&1 | grep -q "Info.plist=not bound" \
    && { echo "ERROR: Info.plist still unsealed after signing; Bluetooth will be denied." >&2; exit 1; }

echo "Built $APP_BUNDLE"

INSTALLED="/Applications/$APP_NAME.app"
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1
rm -rf "$INSTALLED"
cp -R "$APP_BUNDLE" "$INSTALLED"
echo "Installed to $INSTALLED"
open "$INSTALLED"
