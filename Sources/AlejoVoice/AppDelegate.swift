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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // launchd (login agent) and a manual launch can both start a copy; two status
        // items and two global hotkey monitors is never what the user wants.
        guard Self.isOnlyInstance() else {
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
        // Launch at login + come back from a crash. No-op unless running from
        // /Applications, so a copy launched from the DMG never registers itself.
        LoginAgent.ensureInstalled()

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
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir de AlejoVoice", action: #selector(quitApp), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func menuToggle() { toggle() }

    /// "Salir" must actually stay closed: the login agent is `KeepAlive`, so the job has
    /// to be booted out of this login session before exiting — otherwise launchd brings
    /// the process straight back. It loads again at the next login.
    @objc private func quitApp() {
        dictation.cancel()
        LoginAgent.stopForThisSession()
        NSApp.terminate(nil)
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
            } catch {
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
    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
