#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$ROOT_DIR/build/dmg"
APP_PATH="$DERIVED_DATA/Build/Products/Release/AntiScratch.app"
DMG_PATH="$DIST_DIR/AntiScratch-1.0.0.dmg"

rm -rf "$DERIVED_DATA" "$STAGING_DIR"
mkdir -p "$DIST_DIR" "$STAGING_DIR"

xcodebuild \
  -project "$ROOT_DIR/AntiScratch.xcodeproj" \
  -scheme AntiScratch \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

codesign --force --deep --sign - "$APP_PATH"
ditto "$APP_PATH" "$STAGING_DIR/AntiScratch.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname AntiScratch \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

codesign --verify --deep --strict "$STAGING_DIR/AntiScratch.app"
hdiutil verify "$DMG_PATH"
echo "Created $DMG_PATH"
