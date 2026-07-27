# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

AlejoVoice — local voice dictation menu-bar app for macOS (Apple Silicon only). Double-tap a modifier → orb appears → speak → text is written where the cursor is. Everything runs on-device: whisper.cpp + Metal, no network except the one-time model download. UI strings are Spanish; code and comments are English.

## Commands

```bash
# One-time per checkout: clone + build the vendored whisper.cpp static libs the Swift
# package links against (pinned commit). vendor/ is gitignored, so nothing compiles
# before this runs. CI runs the same script.
./scripts/bootstrap_whisper.sh

swift build -c release --arch arm64   # fast compile check
./scripts/build_app.sh                # dist/: app + DMG + update zip (--no-dmg, --restyle)
./scripts/update.sh                   # update /Applications from the working copy (dev)
./scripts/release.sh 1.2.0            # VERSION + tag + push → CI builds and publishes
./scripts/setup_signing.sh            # one-time per machine (see Signing)
./scripts/export_signing_secrets.sh   # same identity into Actions secrets
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

## Distribution: install once, update in place

`VERSION` at the repo root is the single source of truth — `build_app.sh` injects it into `CFBundleVersion`/`CFBundleShortVersionString` and into the DMG/zip names. Bump it through `scripts/release.sh`, never by editing the Info.plist.

The shape of the whole pipeline:

- **First install only**: the DMG, which also ships `Instalar AlejoVoice.command` — it copies the app to `/Applications` and clears `com.apple.quarantine`. Without a paid Developer ID the app cannot be notarized, so a browser-downloaded copy is refused by Gatekeeper ("Apple could not verify…"); clearing the flag is the whole fix. The updater does the same to the bundles it downloads. `scripts/release.sh <version>` tags and pushes; `.github/workflows/release.yml` builds on a `macos-15` (arm64) runner and attaches `AlejoVoice-<v>-arm64.dmg` + `AlejoVoice-<v>-arm64.zip` to the GitHub release. Repo is public so the updater can read the API unauthenticated.
- **Every update after that**: `Updater` (Ajustes → Buscar actualizaciones) reads `releases/latest`, downloads the **zip** asset, verifies signature + bundle id, then execs a detached shell script that waits for the app to exit, `rsync`s the new bundle over `/Applications/AlejoVoice.app` and relaunches. Same path + same bundle id is what makes macOS treat it as an update and keep the TCC grants. A running app cannot overwrite itself — hence the detached script.
- `scripts/update.sh` is the local/dev equivalent (build working copy → swap in place), no release involved.
- **Login agent**: `LoginAgent` registers `Contents/Library/LaunchAgents/com.alejo.alejovoice.plist` (written by `build_app.sh`) through `SMAppService`. A plist in `~/Library/LaunchAgents` pointing at the inner executable works too, but macOS then lists the job as a bare binary with a generic icon instead of the app — don't go back to that.

Two things are load-bearing and easy to break:

- **Signing identity stability.** `scripts/setup_signing.sh` creates a self-signed `AlejoVoice Self Signed` identity and stashes the p12 under `~/Library/Application Support/AlejoVoice/signing/`; `scripts/export_signing_secrets.sh` pushes it to Actions as `MACOS_CERT_P12`/`MACOS_CERT_PASSWORD`, and the release workflow imports and trusts it. Without those secrets CI signs ad-hoc, the cdhash changes every build, and TCC re-prompts every user for Microphone + Accessibility after each update. Both signing paths pin `--identifier com.alejo.alejovoice`.
- **DMG window styling.** The pretty installer window (background, icon positions, hidden toolbar) lives in the volume's `.DS_Store`, which only Finder can author — impossible on a headless runner. `scripts/dmg/DS_Store` is a committed copy that `build_app.sh` drops into the staging folder; `--restyle` re-authors it via AppleScript on a GUI machine and saves it back. Two gotchas already paid for: the background must be set as `POSIX file` (the `file ".background:background.tiff"` colon form fails `-10006` on current macOS), and the volume must be mounted under `/Volumes` (Finder cannot see a private `-mountpoint`). Also: the background art is drawn mid-tone on purpose — Finder paints icon labels black in light mode and white in dark mode and that color is not settable, so a near-black background made the labels vanish.
