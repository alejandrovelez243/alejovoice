#!/bin/bash
# Builds AlejoVoice.app (arm64) in dist/. Pass --dmg to also create a DMG.
# Version comes from the VERSION file at the repo root.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="AlejoVoice"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
# Stable signing identity created by scripts/setup_signing.sh (optional).
SIGN_IDENTITY_NAME="AlejoVoice Self Signed"

MAKE_DMG=0
[[ "${1:-}" == "--dmg" ]] && MAKE_DMG=1

echo "==> Building AlejoVoice $VERSION (release, arm64)"
swift build -c release --arch arm64

echo "==> Assembling app bundle"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/arm64-apple-macosx/release/$APP_NAME" "$APP/Contents/MacOS/"
cp scripts/Info.plist "$APP/Contents/"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"

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

# A stable signing identity keeps the app's code identity constant across rebuilds,
# so macOS reuses the Microphone/Accessibility grants instead of asking again.
# Ad-hoc signatures change every build, which is why permissions used to reset.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY_NAME"; then
  echo "==> Signing with '$SIGN_IDENTITY_NAME'"
  codesign --force --deep --options runtime \
    --identifier com.alejo.alejovoice \
    --sign "$SIGN_IDENTITY_NAME" "$APP"
else
  echo "==> Signing ad-hoc (run scripts/setup_signing.sh once to keep permissions across updates)"
  codesign --force --deep --identifier com.alejo.alejovoice --sign - "$APP"
fi

if [[ $MAKE_DMG == 1 ]]; then
  echo "==> Creating DMG"
  DMG="$DIST/$APP_NAME-$VERSION-arm64.dmg"
  DMG_DIR="$(mktemp -d)"
  cp -R "$APP" "$DMG_DIR/"
  ln -s /Applications "$DMG_DIR/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$DMG_DIR"
  echo "    $DMG"
fi

echo "==> Done: $APP"
