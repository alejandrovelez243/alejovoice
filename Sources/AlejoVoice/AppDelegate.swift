import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkey = HotkeyManager()
    private let dictation = DictationController()
    private let panelModel = PanelModel()
    private var panel: RecordingPanel!
    private var settingsWindow: NSWindow?
    private var isBusy = false // transcribing tail or downloading
    private var accessibilityTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // launchd (login agent) and a manual launch can both start a copy; two status
        // items and two global hotkey monitors is never what the user wants.
        Log.write("launch pid=\(ProcessInfo.processInfo.processIdentifier) "
            + "bundle=\(Bundle.main.bundlePath) "
            + "version=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") "
            + "ax=\(AXIsProcessTrusted())")
        guard Self.isOnlyInstance() else {
            Log.write("another instance is already running — exiting")
            NSApp.terminate(nil)
            return
        }

        setupStatusItem()

        panel = RecordingPanel(
            model: panelModel,
            onStop: { [weak self] in self?.stopAndPaste() },
            onCancel: { [weak self] in self?.cancel() }
        )

        dictation.onLevel = { [weak self] level in
            self?.panelModel.push(level: level)
        }
        dictation.onPartialText = { [weak self] text in
            self?.panelModel.partialText = text
        }
        dictation.onFinished = { [weak self] text in
            self?.handleFinished(text)
        }

        hotkey.onDoubleTap = { [weak self] in self?.toggle() }
        hotkey.start()

        requestAccessibilityIfNeeded()
        // Plain login item. No-op unless running from /Applications, so a copy launched
        // from the DMG never registers itself.
        LoginAgent.ensureInstalled()

        // Ask for the microphone up front: a dictation app is useless without it, and
        // the prompt is far more likely to be seen at launch than mid-dictation.
        AudioRecorder.requestPermission { granted in
            Log.write("startup microphone permission granted=\(granted)")
        }

        if ModelManager.isModelInstalled {
            WhisperEngine.shared.preload()
        } else {
            downloadModel()
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "AlejoVoice")
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Iniciar / detener dictado", action: #selector(menuToggle), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Buscar actualizaciones…", action: #selector(checkForUpdates), keyEquivalent: "")
        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: "Conceder Accesibilidad…",
                         action: #selector(openAccessibilitySettings), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir de AlejoVoice", action: #selector(quitApp), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func menuToggle() { toggle() }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey.stop()
        dictation.cancel()
        UserDefaults.standard.synchronize()
        // ggml's Metal backend aborts inside its own static destructor at exit
        // (ggml_metal_rsets_free → ggml_abort), so a normal quit died with SIGABRT —
        // which the KeepAlive login agent then read as a crash and relaunched the app
        // in a loop. Leave immediately instead of running C++ destructors.
        _exit(0)
    }

    private static func isOnlyInstance() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return true }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .allSatisfy { $0.processIdentifier == me }
    }

    @MainActor
    @objc private func checkForUpdates() {
        openSettings()
        Updater.shared.check()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "AlejoVoice — Ajustes"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Dictation flow

    private func toggle() {
        if dictation.isActive {
            stopAndPaste()
        } else if !isBusy {
            startDictation()
        }
    }

    private func startDictation() {
        guard ModelManager.isModelInstalled else {
            downloadModel()
            return
        }
        AudioRecorder.requestPermission { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.showError("Sin permiso de micrófono. Actívalo en Ajustes del Sistema → Privacidad → Micrófono.")
                return
            }
            do {
                WhisperEngine.shared.preload()
                try self.dictation.start()
                self.panelModel.reset()
                self.panelModel.state = .listening
                self.panel.showCentered()
                Log.write("panel shown visible=\(self.panel.isVisible)")
            } catch {
                Log.write("startDictation failed: \(error.localizedDescription)")
                self.showError("No se pudo iniciar la grabación: \(error.localizedDescription)")
            }
        }
    }

    private func stopAndPaste() {
        guard dictation.isActive else { return }
        isBusy = true
        panelModel.state = .transcribing
        dictation.finish()
    }

    private func handleFinished(_ text: String) {
        // Reached either from stopAndPaste or from silence auto-stop.
        Log.write("finished chars=\(text.count)")
        isBusy = false
        panel.orderOut(nil)
        guard !text.isEmpty else { return }
        if Paster.insert(text) == .clipboard {
            showError("Texto copiado al portapapeles (Cmd+V para pegar). Para escritura automática: Ajustes del Sistema → Privacidad y seguridad → Accesibilidad → activa AlejoVoice.")
        }
    }

    private func cancel() {
        dictation.cancel()
        isBusy = false
        panel.orderOut(nil)
    }

    // MARK: - Model download

    private func downloadModel() {
        isBusy = true
        panelModel.state = .downloading(0)
        panel.showCentered()
        let manager = ModelManager.shared
        manager.onProgress = { [weak self] progress in
            self?.panelModel.state = .downloading(progress)
        }
        manager.onFinished = { [weak self] result in
            guard let self else { return }
            self.isBusy = false
            switch result {
            case .success:
                self.panel.orderOut(nil)
                WhisperEngine.shared.preload()
            case .failure(let error):
                self.showError("Error descargando el modelo: \(error.localizedDescription)")
            }
        }
        manager.download()
    }

    // MARK: - Helpers

    private func showError(_ message: String) {
        panelModel.state = .error(message)
        panel.showCentered()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, case .error = self.panelModel.state else { return }
            self.panel.orderOut(nil)
        }
    }

    /// Only ever prompts when the permission is actually missing — passing the prompt
    /// option unconditionally re-opened System Settings on every single launch.
    ///
    /// The prompt is also unreliable: macOS shows it once per app and then suppresses
    /// it, so the app must not depend on it. Hence the menu item that opens the pane
    /// directly, and the poll below that picks the permission up without a relaunch.
    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        watchForAccessibility()
    }

    /// Global event monitors installed while untrusted never receive events, and macOS
    /// does not restart the app when the toggle is flipped. Re-arm them ourselves.
    private func watchForAccessibility() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.accessibilityTimer = nil
            self?.hotkey.start()
        }
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        watchForAccessibility()
    }
}
