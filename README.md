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

## Instalación y actualizaciones

Un solo comando instala **y** actualiza, siempre en `/Applications/AlejoVoice.app` (mismo bundle id, misma ruta → macOS lo ve como actualización, no como app nueva; no hay que borrar la vieja ni montar DMG):

```bash
./scripts/setup_signing.sh   # una sola vez: identidad de firma estable
./scripts/install.sh         # build + actualizar en sitio + agente de login
```

`install.sh` cierra la instancia en marcha, reemplaza el bundle en sitio y vuelve a arrancar. Instala también un LaunchAgent (`~/Library/LaunchAgents/com.alejo.alejovoice.plist`) que arranca la app al iniciar sesión y la reinicia si se cae — "Salir de AlejoVoice" desde el menú sí la deja cerrada. Usa `./scripts/install.sh --no-agent` si no quieres eso.

Para subir versión: edita `VERSION` (ej. `1.2.0`) y corre `install.sh`. `build_app.sh --dmg` genera un DMG con el número de versión si quieres distribuirlo.

Sin `setup_signing.sh` la app va firmada ad-hoc y su identidad cambia en cada build: macOS vuelve a pedir permisos de Micrófono y Accesibilidad cada vez que actualizas.

## Build desde código

Requisitos: macOS 13+, Apple Silicon, Swift 6+, cmake (`brew install cmake`).

```bash
# 1. Compilar whisper.cpp (una vez)
git clone --depth 1 https://github.com/ggml-org/whisper.cpp vendor/whisper.cpp
cmake -S vendor/whisper.cpp -B vendor/whisper.cpp/build \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON
cmake --build vendor/whisper.cpp/build -j --target whisper-cli

# 2. App (añade --dmg para generar también el DMG)
./scripts/build_app.sh
```

Salida en `dist/`.

## Arquitectura

- Swift/SwiftUI nativo, sin dependencias externas. Menu bar app (`LSUIElement`).
- `HotkeyManager` — monitor global de `flagsChanged`, detecta doble tap del modificador elegido.
- `AudioRecorder` — AVAudioEngine → chunks Float32 16 kHz mono en streaming. Engine nuevo en cada dictado y formato validado antes del tap (un engine reusado tras cambiar de dispositivo de audio hacía que `installTap` lanzara una excepción ObjC y el proceso abortara).
- `WhisperEngine` — libwhisper linkeada estática (Metal embebido), modelo cargado una vez en memoria + warmup al arrancar.
- `DictationController` — segmenta por pausas de voz (~0.8 s) y transcribe cada segmento mientras sigues hablando; silencio de 2.5 s = auto-stop y pega de inmediato.
- `Paster` — escribe el texto **sin tocar el portapapeles**: inserción vía Accesibilidad (`kAXSelectedText`) y, si la app no la acepta, teclas Unicode sintéticas. El portapapeles solo se usa si falta el permiso de Accesibilidad.
- `RecordingPanel` — panel transparente no-activante con orbe estilo Siri (el foco se queda en tu app).
