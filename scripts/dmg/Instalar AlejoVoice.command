#!/bin/bash
# Ships inside the DMG. Copies the app to /Applications and clears the quarantine
# flag the browser put on the download — without a (paid) Developer ID signature
# Gatekeeper otherwise refuses to launch it: "Apple could not verify AlejoVoice".
set -euo pipefail

APP_NAME="AlejoVoice"
SOURCE="$(cd "$(dirname "$0")" && pwd)/$APP_NAME.app"
TARGET="/Applications/$APP_NAME.app"

printf '\n  Instalando %s…\n\n' "$APP_NAME"

if [[ ! -d "$SOURCE" ]]; then
  echo "  No encuentro $APP_NAME.app junto a este instalador."
  echo "  Ejecuta este archivo desde dentro del DMG."
  read -r -p "  Enter para cerrar." _
  exit 1
fi

# A running instance would block the replace.
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
launchctl bootout "gui/$UID/com.alejo.alejovoice" 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -x "$APP_NAME" >/dev/null || break
  sleep 0.3
done
pkill -x "$APP_NAME" 2>/dev/null || true

echo "  → Copiando a /Applications"
rm -rf "$TARGET"
cp -R "$SOURCE" "$TARGET"

echo "  → Quitando la marca de cuarentena"
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

echo "  → Abriendo AlejoVoice"
open "$TARGET"

cat <<'TEXT'

  Listo. El icono de onda aparece en la barra de menú.

  macOS pedirá dos permisos la primera vez:
    · Micrófono       — para grabar tu voz
    · Accesibilidad   — para el atajo global y escribir el texto

  Uso: doble tap ⌘ derecho para dictar.
  Actualizar: Ajustes → Buscar actualizaciones (ya no hace falta este DMG).

TEXT
read -r -p "  Enter para cerrar esta ventana." _
