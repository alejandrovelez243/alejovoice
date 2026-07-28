import AppKit
import ServiceManagement

/// Launch at login, as a plain login item (`SMAppService.mainApp`).
///
/// This deliberately does **not** use a `KeepAlive` LaunchAgent any more. A launchd-owned
/// process is not a regular GUI app as far as TCC is concerned, and macOS then silently
/// skips the Microphone and Accessibility prompts — the permissions could never be
/// granted on a fresh install. The agent only existed to restart the app after crashes
/// that are now fixed at the source (stale `AVAudioEngine` on device change, and ggml's
/// Metal backend aborting in its static destructor at exit).
enum LoginAgent {
    static let label = "com.alejo.alejovoice"

    private static var legacyPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func ensureInstalled() {
        // Only manage this for a real install: never register a DMG volume or a build
        // directory as a login item.
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }

        removeLegacyAgents()

        let app = SMAppService.mainApp
        guard app.status != .enabled else { return }
        do {
            try app.register()
        } catch {
            NSLog("AlejoVoice: could not register login item — \(error.localizedDescription)")
        }
    }

    static func remove() {
        removeLegacyAgents()
        try? SMAppService.mainApp.unregister()
    }

    /// Clears both earlier mechanisms: the bundled LaunchAgent registered through
    /// SMAppService, and the hand-written plist in ~/Library/LaunchAgents. Either one
    /// would keep launching a second, launchd-owned copy.
    private static func removeLegacyAgents() {
        let agent = SMAppService.agent(plistName: "\(label).plist")
        if agent.status != .notRegistered {
            try? agent.unregister()
        }
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        if FileManager.default.fileExists(atPath: legacyPlistURL.path) {
            try? FileManager.default.removeItem(at: legacyPlistURL)
        }
    }

    private static func launchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
