#!/bin/bash
# Builds AlejoVoice.app (arm64) and a distributable DMG in dist/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="AlejoVoice"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building Swift binary (release, arm64)"
swift build -c release --arch arm64

echo "==> Assembling app bundle"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/arm64-apple-macosx/release/$APP_NAME" "$APP/Contents/MacOS/"
cp scripts/Info.plist "$APP/Contents/"

echo "==> Generating icon"
ICON_TMP="$(mktemp -d)"
swift scripts/make_icon.swift "$ICON_TMP/icon_1024.png" >/dev/null
ICONSET="$ICON_TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICON_TMP"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "==> Creating DMG"
DMG="$DIST/$APP_NAME-1.0.0-arm64.dmg"
DMG_DIR="$(mktemp -d)"
cp -R "$APP" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DMG_DIR"

echo "==> Done:"
echo "    $APP"
echo "    $DMG"
