#!/bin/bash
# Updates the installed /Applications/AlejoVoice.app from the current working copy,
# without publishing a release. This is the local/dev path — the user-facing path is
# Ajustes → Buscar actualizaciones (see scripts/release.sh).
#
# Same bundle path + bundle id => macOS sees an update, not a second app, and the
# Microphone/Accessibility grants stay.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="AlejoVoice"
TARGET="/Applications/$APP_NAME.app"
LABEL="com.alejo.alejovoice"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"

if [[ ! -d "$TARGET" ]]; then
  echo "No hay nada instalado en $TARGET."
  echo "Primera instalación: ./scripts/build_app.sh y abre dist/$APP_NAME-$VERSION-arm64.dmg"
  exit 1
fi

bash scripts/build_app.sh --no-dmg

echo "==> Stopping the running instance"
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
for _ in $(seq 1 10); do
  pgrep -x "$APP_NAME" >/dev/null || break
  sleep 0.3
done
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.3

echo "==> Updating $TARGET"
rsync -a --delete "$ROOT/dist/$APP_NAME.app/" "$TARGET/"
codesign --verify --deep "$TARGET" && echo "    signature OK"

# The app reinstalls its own login agent on launch; just start it.
open "$TARGET"
echo "==> AlejoVoice $VERSION corriendo desde $TARGET"
