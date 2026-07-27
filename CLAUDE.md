# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

AlejoVoice — local voice dictation menu-bar app for macOS (Apple Silicon only). Double-tap a modifier → orb appears → speak → text is written where the cursor is. Everything runs on-device: whisper.cpp + Metal, no network except the one-time model download. UI strings are Spanish; code and comments are English.

## Commands

```bash
# One-time: build the vendored whisper.cpp static libs the Swift package links against.
# vendor/ is gitignored — a fresh clone MUST do this before anything compiles.
git clone --depth 1 https://github.com/ggml-org/whisper.cpp vendor/whisper.cpp
cmake -S vendor/whisper.cpp -B vendor/whisper.cpp/build \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON
cmake --build vendor/whisper.cpp/build -j --target whisper-cli

swift build -c release --arch arm64   # fast compile check
./scripts/build_app.sh                # dist/AlejoVoice.app (add --dmg for a DMG)
./scripts/setup_signing.sh            # one-time, per machine (see Signing)
./scripts/install.sh                  # build + update /Applications in place + login agent
```

`swift build` must be `--arch arm64` — the linker flags in `Package.swift` point at arm64-only static libs. Expect `built for newer 'macOS' version (26.0)` linker warnings from the ggml objects; harmless.

There is no test target. The only automated check is a hidden smoke test on the built binary:

```bash
.build/arm64-apple-macosx/release/AlejoVoice --transcribe some16k-mono-16bit.wav
```

It loads the model, transcribes, prints timings, exits — it bypasses `NSApplication` entirely (see `main.swift`). UI/permission behavior can only be verified by running the installed app.

## Architecture

Single executable target `AlejoVoice` + a thin `CWhisper` C shim exposing whisper.h. `LSUIElement` app: no dock icon, `.accessory` activation policy, lives in the status bar (`AppDelegate`).

Dictation flow, one hop per file:

`HotkeyManager` (global `flagsChanged` monitor, double-tap of the chosen modifier) → `AppDelegate.toggle()` → `DictationController.start()` → `AudioRecorder` (AVAudioEngine tap → 16 kHz mono Float32 chunks + RMS) → `DictationController` segments on ~0.8 s pauses and hands each segment to `WhisperEngine` **while the user keeps talking** → `AppDelegate.handleFinished` → `Paster`.

Facts that are not obvious from any single file:

- **Streaming segmentation is the core design.** `DictationController` closes a segment at a short pause and transcribes it in the background, so the final text is ready almost immediately when dictation ends. Segments are keyed by index in `parts` and reassembled in order (`orderedText()`); each segment's whisper `initial_prompt` is the text so far, for continuity. `checkDone()` only fires `onFinished` when `finishing && pendingCount == 0` — so the "stop" path waits for in-flight segments. 2.5 s silence auto-stops; 8 s with no speech at all cancels.
- **`WhisperEngine` is a singleton with one long-lived `whisper_context` on a serial queue.** Serial ordering is what makes result order match submission order. `preload()` also runs a 1 s silent inference once so Metal kernels compile before the first real segment.
- **`AudioRecorder` builds a fresh `AVAudioEngine` per `start()` and validates the input format before installing the tap.** This is a crash fix, not style: a reused engine whose audio device changed (headphones plugged in, device slept) reports a 0 Hz / 0-channel format, and `installTap` then raises an ObjC exception that Swift cannot catch — the process aborts (SIGABRT). Never reintroduce a shared/persistent engine, and never install a tap without the `isUsable(_:)` check. The `AVAudioEngineConfigurationChange` observer finalizes an in-flight dictation instead of feeding the converter mismatched buffers.
- **`Paster` must not use the clipboard on the happy path.** Order: Accessibility insertion into the focused element (`kAXSelectedText`, verified by reading the value back — an app that reports the attribute settable and silently drops the write must fall through), then synthetic Unicode keystrokes (`keyboardSetUnicodeString`, `CGEventSource(stateID: .privateState)` so a still-held ⌘ from the hotkey can't turn text into shortcuts), and only then the clipboard — reserved for the case where Accessibility permission is missing and no other delivery exists.
- **`RecordingPanel` is a borderless `.nonactivatingPanel`** so the orb never steals focus from the app being dictated into. That property is load-bearing: taking focus would break insertion. `PanelModel` is the single `ObservableObject` driving the orb (`RecordingView`), asymmetric level smoothing (fast attack, slow release) included.
- **Model download is lazy and user-visible.** `ModelManager` fetches `ggml-large-v3-turbo-q5_0.bin` (~547 MB) from Hugging Face into `~/Library/Application Support/AlejoVoice/models/` on first launch, progress shown through the same panel (`PanelState.downloading`).
- Settings are three `UserDefaults` values behind `AppSettings` (hotkey choice, whisper language). No settings file, no schema.

## Permissions

Microphone (recording) and Accessibility (global hotkey monitor + text insertion) are both required. Missing Accessibility silently degrades the app to the clipboard fallback path, so when debugging "text didn't appear", check `AXIsProcessTrusted()` first.

## Signing, versioning, updates

`VERSION` at the repo root is the single source of truth — `build_app.sh` injects it into `CFBundleVersion`/`CFBundleShortVersionString` and into the DMG name. Bump it there, nowhere else.

`scripts/install.sh` updates `/Applications/AlejoVoice.app` **in place** (`rsync -a --delete`, same path, same bundle id `com.alejo.alejovoice`) so macOS sees an update rather than a second app, and installs a LaunchAgent (`com.alejo.alejovoice`) with `RunAtLoad` + `KeepAlive`/`SuccessfulExit=false` — restart on crash, stay closed on a clean quit from the menu.

`scripts/setup_signing.sh` creates a self-signed `AlejoVoice Self Signed` identity; `build_app.sh` uses it when present and falls back to ad-hoc. This matters because ad-hoc signatures change every build, so TCC keys on the changing cdhash and re-prompts for Microphone/Accessibility on every update. Keep the bundle identifier pinned via `--identifier com.alejo.alejovoice` in both signing paths.
