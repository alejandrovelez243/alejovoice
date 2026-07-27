# AlejoVoice

Dictado por voz local para macOS (Apple Silicon). Habla, para, y el texto aparece donde tengas el cursor. Todo corre en tu máquina con [whisper.cpp](https://github.com/ggml-org/whisper.cpp) + Metal — sin internet, sin API keys.

## Uso

1. **Doble tap ⌘ derecho** → aparece el orbe y empieza a escuchar.
2. Habla. El texto se va transcribiendo en tiempo real (se ve debajo del orbe).
3. Para: **2.5 s de silencio** (auto-stop), **doble tap** otra vez, o **clic en el orbe** → el texto se pega al instante donde esté el cursor.
4. La **✕** (hover sobre el orbe) cancela sin pegar.

Vive en la barra de menú (icono de onda de sonido). Desde ahí: iniciar/detener, ajustes (atajo e idioma), salir.

## Primer arranque

- Descarga el modelo Whisper (`large-v3-turbo-q5_0`, ~547 MB) una sola vez → `~/Library/Application Support/AlejoVoice/models/`.
- Pide permisos: **Micrófono** y **Accesibilidad** (necesario para el atajo global y el auto-paste). Concédelos en Ajustes del Sistema → Privacidad y seguridad.

## Instalar

### [⬇︎ Descargar AlejoVoice (Apple Silicon)](https://github.com/alejandrovelez243/alejovoice/releases/latest/download/AlejoVoice-arm64.dmg)

Ese enlace apunta siempre a la última versión publicada (GitHub resuelve `releases/latest/download/…` a la release más reciente, y el workflow sube una copia con nombre fijo para eso). Solo se usa la primera vez.

Abre el DMG y **doble clic en "Instalar AlejoVoice"**: copia la app a Aplicaciones, le quita la marca de cuarentena y la abre. Si macOS bloquea también el instalador: clic derecho → *Abrir*.

Por qué hace falta ese paso: la app no está notarizada (requiere cuenta de developer de pago), así que Gatekeeper rechaza cualquier copia que venga marcada por el navegador con **"Apple could not verify AlejoVoice"**. Si prefieres arrastrarla a mano, quita la marca tú:

```sh
xattr -dr com.apple.quarantine /Applications/AlejoVoice.app
```

Las actualizaciones desde la propia app no pasan por Gatekeeper, así que esto es solo para la instalación inicial.

Al arrancar desde `/Applications` la app se registra sola como agente de login (vía `SMAppService`, con el plist dentro del bundle): arranca al iniciar sesión y vuelve si se cae. "Salir de AlejoVoice" desde el menú la deja cerrada.

## Actualizar

**AlejoVoice → Ajustes → Buscar actualizaciones.** Lee la última release de GitHub, descarga el `.zip`, reemplaza la app en sitio y se reinicia. No hay que bajar DMG ni borrar la versión vieja.

## Publicar una versión (para el autor)

```bash
./scripts/release.sh 1.2.0            # VERSION + tag + push → CI construye y publica
./scripts/release.sh 1.2.0 --local    # construir y publicar desde este Mac
```

GitHub Actions (`.github/workflows/build.yml`) compila en un runner arm64 y, cuando el push es de un tag `v*`, sube el DMG y el zip a la release en el mismo run. Eso es lo que ve el botón "Buscar actualizaciones".

Firma: por defecto ad-hoc, y una firma ad-hoc cambia en cada build, así que macOS vuelve a pedir Micrófono y Accesibilidad tras cada actualización. Para evitarlo, una vez:

```bash
./scripts/setup_signing.sh            # identidad self-signed estable en el llavero
./scripts/export_signing_secrets.sh   # la misma identidad como secrets de Actions
```

## Build desde código

Requisitos: macOS 13+, Apple Silicon, Swift 6+, cmake (`brew install cmake`).

```bash
./scripts/bootstrap_whisper.sh   # clona y compila whisper.cpp (commit pinneado)
./scripts/build_app.sh           # app + DMG + zip en dist/
./scripts/update.sh              # actualiza /Applications con el working copy (dev)
```

`build_app.sh --no-dmg` salta el DMG; `--restyle` re-genera el layout de la ventana del DMG con Finder y lo guarda en `scripts/dmg/DS_Store` (lo que permite que CI produzca el mismo DMG sin sesión gráfica).

## Arquitectura

- Swift/SwiftUI nativo, sin dependencias externas. Menu bar app (`LSUIElement`).
- `HotkeyManager` — monitor global de `flagsChanged`, detecta doble tap del modificador elegido.
- `AudioRecorder` — AVAudioEngine → chunks Float32 16 kHz mono en streaming. Engine nuevo en cada dictado y formato validado antes del tap (un engine reusado tras cambiar de dispositivo de audio hacía que `installTap` lanzara una excepción ObjC y el proceso abortara).
- `WhisperEngine` — libwhisper linkeada estática (Metal embebido), modelo cargado una vez en memoria + warmup al arrancar.
- `DictationController` — segmenta por pausas de voz (~0.8 s) y transcribe cada segmento mientras sigues hablando; silencio de 2.5 s = auto-stop y pega de inmediato.
- `Paster` — escribe el texto **sin tocar el portapapeles**: inserción vía Accesibilidad (`kAXSelectedText`) y, si la app no la acepta, teclas Unicode sintéticas. El portapapeles solo se usa si falta el permiso de Accesibilidad.
- `RecordingPanel` — panel transparente no-activante con orbe estilo Siri (el foco se queda en tu app).
- `Updater` — lee la última release vía API de GitHub, descarga el zip, verifica firma y bundle id, y delega el reemplazo a un script suelto (una app no puede sobrescribirse a sí misma en marcha).
- `LoginAgent` — la app instala su propio LaunchAgent al arrancar desde `/Applications`.
