#!/bin/bash
# Builds AlejoVoice and updates the copy already in /Applications, in place.
#
# Same bundle path, same bundle id, same signing identity => macOS sees an update,
# not a second app. No DMG to mount, nothing to drag, no old copy to delete.
#
#   scripts/install.sh              build + update + (re)install the login agent
#   scripts/install.sh --no-agent   skip the launch-at-login / auto-restart agent
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="AlejoVoice"
TARGET="/Applications/$APP_NAME.app"
LABEL="com.alejo.alejovoice"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
WITH_AGENT=1
[[ "${1:-}" == "--no-agent" ]] && WITH_AGENT=0

bash scripts/build_app.sh

echo "==> Stopping the running instance"
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -x "$APP_NAME" >/dev/null || break
  sleep 0.3
done
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.3

echo "==> Updating $TARGET"
mkdir -p "$TARGET"
# --delete removes files dropped between versions; the bundle directory itself is
# reused so the path macOS has permissions on never changes.
rsync -a --delete "$ROOT/dist/$APP_NAME.app/" "$TARGET/"
codesign --verify --deep "$TARGET" && echo "    signature OK"

if [[ $WITH_AGENT == 1 ]]; then
  echo "==> Installing login agent (starts at login, restarts if it ever crashes)"
  mkdir -p "$(dirname "$AGENT")"
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$TARGET/Contents/MacOS/$APP_NAME</string>
	</array>
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
</dict>
</plist>
PLIST
  launchctl bootstrap "gui/$UID" "$AGENT"
else
  open "$TARGET"
fi

echo "==> AlejoVoice $VERSION installed at $TARGET"
