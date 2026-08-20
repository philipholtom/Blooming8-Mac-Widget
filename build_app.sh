#!/bin/bash
# Builds and installs the two Blooming8 products:
#   Blooming8Widget.app  menu bar widget (LSUIElement, popover)
#   Blooming8.app        full window app (sidebar + gallery grid)
# Both link the shared Blooming8Core library.
#
# Usage: ./build_app.sh [widget|app|all]   (default: all)
set -euo pipefail
cd "$(dirname "$0")"

BUILD_CONFIG="Release"
XCODE_BETA="/Applications/Xcode-beta.app/Contents/Developer"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/Blooming8_Screen_Widget-bemzrgmnicnbnxfhqswrxccqxuqi"
PRODUCTS="$DERIVED_DATA/Build/Products/$BUILD_CONFIG"

TARGET="${1:-all}"

# $1 scheme/binary name, $2 .app bundle name, $3 Info.plist, $4 bundle id
build_product() {
    local scheme="$1" bundle="$2" plist="$3" bundle_id="$4"

    "$XCODE_BETA/usr/bin/xcodebuild" -scheme "$scheme" -configuration "$BUILD_CONFIG" \
        -destination "generic/platform=macOS" build

    rm -rf "$bundle"
    mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
    cp "$PRODUCTS/$scheme" "$bundle/Contents/MacOS/$scheme"
    cp "$plist" "$bundle/Contents/Info.plist"
    cp Resources/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"

    # Codesign the assembled bundle. Without this the only signature is the one
    # the linker applied to the bare executable, before Info.plist was copied in
    # — so the plist is left unsealed ("Info.plist=not bound"). TCC refuses to
    # trust an unsealed NSBluetoothAlwaysUsageDescription and denies Bluetooth
    # outright, which surfaces as CBCentralManager reporting .unauthorized and
    # every BLE wake failing silently. Ad-hoc is enough to seal it.
    codesign --force --sign - --identifier "$bundle_id" "$bundle"
    if codesign -dv "$bundle" 2>&1 | grep -q "Info.plist=not bound"; then
        echo "ERROR: Info.plist still unsealed in $bundle; Bluetooth will be denied." >&2
        exit 1
    fi

    local installed="/Applications/$bundle"
    pkill -x "$scheme" 2>/dev/null || true
    sleep 1
    rm -rf "$installed"
    cp -R "$bundle" "$installed"
    echo "Installed $installed"
}

if [ "$TARGET" = "widget" ] || [ "$TARGET" = "all" ]; then
    build_product "Blooming8Widget" "Blooming8Widget.app" "Info.plist" "com.pholtom.blooming8widget"
fi

if [ "$TARGET" = "app" ] || [ "$TARGET" = "all" ]; then
    build_product "Blooming8App" "Blooming8.app" "Info-App.plist" "com.pholtom.blooming8app"
fi

case "$TARGET" in
    widget) open "/Applications/Blooming8Widget.app" ;;
    app)    open "/Applications/Blooming8.app" ;;
    all)    open "/Applications/Blooming8Widget.app"; open "/Applications/Blooming8.app" ;;
esac
