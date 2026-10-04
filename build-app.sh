#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP_NAME="HandySwift"
BUNDLE_ID="com.user.handyswift"
VERSION="${VERSION:-0.2.0}"
APP_DIR="build/${APP_NAME}.app"
ENTITLEMENTS="build/${APP_NAME}.entitlements"

swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/${APP_NAME}"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "executable not found at $BIN_PATH" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/${APP_NAME}"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>Handy Swift</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>HandySwift needs microphone access to record dictation.</string>
</dict>
</plist>
PLIST

cat > "$ENTITLEMENTS" <<ENTITLEMENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key><true/>
</dict>
</plist>
ENTITLEMENTS

# A stable identity keeps Accessibility/Microphone grants across rebuilds; ad-hoc (-) means
# macOS asks again after every rebuild. Uses an "Apple Development" identity when one exists,
# otherwise ad-hoc. Release DMGs are built with SIGN_IDENTITY=- (see make-dmg.sh).
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
        SIGN_IDENTITY="Apple Development"
    else
        SIGN_IDENTITY="-"
    fi
fi
codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" \
    --identifier "$BUNDLE_ID" \
    --sign "$SIGN_IDENTITY" \
    "$APP_DIR"

echo "Built: $APP_DIR"

# INSTALL=1 copies to ~/Applications, the stable path the login item points at.
if [[ "${INSTALL:-0}" == "1" ]]; then
    pkill -x "$APP_NAME" || true
    rm -rf "$HOME/Applications/${APP_NAME}.app"
    mkdir -p "$HOME/Applications"
    cp -R "$APP_DIR" "$HOME/Applications/"
    echo "Installed: $HOME/Applications/${APP_NAME}.app"
fi
