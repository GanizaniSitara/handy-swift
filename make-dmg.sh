#!/bin/bash
# Builds a release HandySwift.app, ad-hoc signed, and packs it into a drag-to-Applications DMG.
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${VERSION:-0.3.0}"
DMG="build/HandySwift-${VERSION}-macos-arm64.dmg"
STAGE="build/dmg"

VERSION="$VERSION" SIGN_IDENTITY="-" CONFIG=release ./build-app.sh

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/HandySwift.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Handy Swift ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "DMG: $DMG"
