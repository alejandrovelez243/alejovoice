#!/bin/bash
# Builds AlejoVoice.app plus the two distributables, in dist/. Installs nothing.
#
#   dist/AlejoVoice.app                     the bundle
#   dist/AlejoVoice-<version>-arm64.dmg     first-time installer (drag to Applications)
#   dist/AlejoVoice-<version>-arm64.zip     update payload consumed by the in-app updater
#
#   scripts/build_app.sh             app + DMG + zip
#   scripts/build_app.sh --no-dmg    app + zip only (faster; used by update.sh)
#   scripts/build_app.sh --restyle   re-author the DMG window layout with Finder and
#                                    save it to scripts/dmg/DS_Store (needs a GUI
#                                    session; run after changing the layout)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="AlejoVoice"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
# Stable signing identity created by scripts/setup_signing.sh (optional).
SIGN_IDENTITY_NAME="AlejoVoice Self Signed"

MAKE_DMG=1
RESTYLE=0
case "${1:-}" in
  --no-dmg) MAKE_DMG=0 ;;
  --restyle) RESTYLE=1 ;;
esac

echo "==> Building AlejoVoice $VERSION (release, arm64)"
swift build -c release --arch arm64

echo "==> Assembling app bundle"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/arm64-apple-macosx/release/$APP_NAME" "$APP/Contents/MacOS/"
cp scripts/Info.plist "$APP/Contents/"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"

# Login agent shipped inside the bundle and registered with SMAppService, so macOS
# shows the app (name + icon) in Login Items / Background Activity instead of a bare
# executable. BundleProgram is resolved relative to the bundle root.
mkdir -p "$APP/Contents/Library/LaunchAgents"
cat > "$APP/Contents/Library/LaunchAgents/com.alejo.alejovoice.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.alejo.alejovoice</string>
	<key>BundleProgram</key>
	<string>Contents/MacOS/AlejoVoice</string>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<!-- Restart after a crash, but honour "Salir de AlejoVoice" (clean exit). -->
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>ProcessType</key>
	<string>Interactive</string>
	<key>AssociatedBundleIdentifiers</key>
	<array>
		<string>com.alejo.alejovoice</string>
	</array>
</dict>
</plist>
PLIST

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

echo "==> Creating update zip"
ZIP="$DIST/$APP_NAME-$VERSION-arm64.zip"
# ditto (not zip) preserves symlinks and resource forks, so the signature survives.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

if [[ $MAKE_DMG == 1 ]]; then
  DMG="$DIST/$APP_NAME-$VERSION-arm64.dmg"
  VOLNAME="$APP_NAME"
  STAGE="$(mktemp -d)/$APP_NAME"
  mkdir -p "$STAGE/.background"

  echo "==> Rendering installer background"
  swift scripts/make_dmg_background.swift "$ICON_TMP/bg.png" 640 480 "$VERSION" >/dev/null
  swift scripts/make_dmg_background.swift "$ICON_TMP/bg@2x.png" 1280 960 "$VERSION" >/dev/null
  # A multi-representation TIFF is what makes the background crisp on Retina.
  tiffutil -cathidpicheck "$ICON_TMP/bg.png" "$ICON_TMP/bg@2x.png" \
    -out "$STAGE/.background/background.tiff" >/dev/null

  echo "==> Creating DMG"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  # Double-click installer: copies the app AND clears com.apple.quarantine, which is
  # what Gatekeeper trips over on an app that is not notarized (no paid Developer ID).
  cp "$ROOT/scripts/dmg/Instalar $APP_NAME.command" "$STAGE/"
  chmod +x "$STAGE/Instalar $APP_NAME.command"
  # Custom volume icon: the mounted disk shows the app icon, not a generic drive.
  cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

  # The window layout (icon positions, icon size, background, hidden toolbar) lives in
  # the volume's .DS_Store, and only Finder can author one. scripts/dmg/DS_Store is a
  # committed copy of that file, so headless builds (CI) get the styled window too.
  # Regenerate it with --restyle on a machine with a Finder session.
  if [[ $RESTYLE == 0 && -f "$ROOT/scripts/dmg/DS_Store" ]]; then
    cp "$ROOT/scripts/dmg/DS_Store" "$STAGE/.DS_Store"
    STYLE_WITH_FINDER=0
  else
    STYLE_WITH_FINDER=1
  fi

  RW_DMG="$ICON_TMP/rw.dmg"
  hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov \
    -format UDRW -fs HFS+ "$RW_DMG" >/dev/null
  # Mount under /Volumes and let Finder see it: styling is done by AppleScript, and
  # Finder can only address the volume by name (a private -mountpoint is invisible
  # to it, which is why `disk "AlejoVoice"` used to fail).
  hdiutil attach "$RW_DMG" -noverify >/dev/null
  MOUNT="/Volumes/$VOLNAME"

  # Turn on the volume's "has custom icon" Finder flag (byte 8 of FinderInfo, 0x0400)
  # so .VolumeIcon.icns is used. SetFile would need ownership of the volume, which a
  # freshly attached image does not grant.
  xattr -wx com.apple.FinderInfo \
    "0000000000000000040000000000000000000000000000000000000000000000" \
    "$MOUNT" 2>/dev/null || true

if [[ $STYLE_WITH_FINDER == 1 ]]; then
  echo "==> Styling window with Finder"
  # Finder is the only thing that can author the .DS_Store. The background must be
  # addressed as a POSIX file — the classic `file ".background:background.tiff"`
  # colon form fails with -10006 on current macOS. First run may ask for permission
  # to control Finder; if it is denied the DMG still works, it just looks plain.
  STYLED=1
  osascript >/dev/null <<APPLESCRIPT || STYLED=0
tell application "Finder"
	tell disk "$VOLNAME"
		open
		set current view of container window to icon view
		set toolbar visible of container window to false
		set statusbar visible of container window to false
		set the bounds of container window to {240, 140, 880, 620}
		set opts to the icon view options of container window
		set arrangement of opts to not arranged
		set icon size of opts to 112
		set text size of opts to 13
		set background picture of opts to POSIX file "$MOUNT/.background/background.tiff"
		-- Let Finder notice every freshly copied item before positioning it, otherwise
		-- \`set position\` fails with -10006 on the last file written.
		delay 1
		set position of item "$APP_NAME.app" of container window to {160, 200}
		set position of item "Applications" of container window to {480, 200}
		set position of item "Instalar $APP_NAME.command" of container window to {320, 372}
		delay 1
		-- Both of these throw "Finder is busy" now and then; the layout is already in
		-- the .DS_Store by this point, so a failure here must not fail the build.
		try
			update without registering applications
		end try
		delay 1
		try
			close
		end try
	end tell
end tell
APPLESCRIPT

  if [[ $STYLED == 1 ]]; then
    # Keep the freshly authored layout so headless builds can reuse it.
    mkdir -p "$ROOT/scripts/dmg"
    cp "$MOUNT/.DS_Store" "$ROOT/scripts/dmg/DS_Store" \
      && echo "    saved scripts/dmg/DS_Store"
  else
    echo "    (Finder styling failed — kept the committed scripts/dmg/DS_Store)"
    cp "$ROOT/scripts/dmg/DS_Store" "$MOUNT/.DS_Store" 2>/dev/null || true
  fi
fi

  sync
  # Finder can hold the volume for a moment after closing the window.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    hdiutil detach "$MOUNT" >/dev/null 2>&1 && break
    sleep 1
  done
  [[ -d "$MOUNT" ]] && hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
  rm -f "$DMG"
  hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
  rm -rf "$STAGE"
  echo "    $DMG"
fi

rm -rf "$ICON_TMP"

echo "==> Done"
echo "    $APP"
echo "    $ZIP"
