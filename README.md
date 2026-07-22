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

## Instalación

Abre `dist/AlejoVoice-1.0.0-arm64.dmg` y arrastra la app a Applications.

La app va firmada ad-hoc (sin cuenta de developer): la primera vez macOS puede bloquearla. Clic derecho → Abrir, o en Ajustes del Sistema → Privacidad y seguridad → "Abrir de todas formas".

## Build desde código

Requisitos: macOS 13+, Apple Silicon, Swift 6+, cmake (`brew install cmake`).

```bash
# 1. Compilar whisper.cpp (una vez)
git clone --depth 1 https://github.com/ggml-org/whisper.cpp vendor/whisper.cpp
cmake -S vendor/whisper.cpp -B vendor/whisper.cpp/build \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON
cmake --build vendor/whisper.cpp/build -j --target whisper-cli

# 2. App + DMG
./scripts/build_app.sh
```

Salida en `dist/`.

## Arquitectura

- Swift/SwiftUI nativo, sin dependencias externas. Menu bar app (`LSUIElement`).
- `HotkeyManager` — monitor global de `flagsChanged`, detecta doble tap del modificador elegido.
- `AudioRecorder` — AVAudioEngine → chunks Float32 16 kHz mono en streaming.
- `WhisperEngine` — libwhisper linkeada estática (Metal embebido), modelo cargado una vez en memoria + warmup al arrancar.
- `DictationController` — segmenta por pausas de voz (~0.8 s) y transcribe cada segmento mientras sigues hablando; silencio de 2.5 s = auto-stop y pega de inmediato.
- `Paster` — clipboard + Cmd+V sintético; restaura el clipboard anterior.
- `RecordingPanel` — panel transparente no-activante con orbe estilo Siri (el foco se queda en tu app).
