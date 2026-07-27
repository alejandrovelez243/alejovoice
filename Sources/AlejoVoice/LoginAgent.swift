import AppKit
import ServiceManagement

/// Launch at login + come back after a crash (`KeepAlive`/`SuccessfulExit=false`, so
/// quitting from the menu keeps it closed).
///
/// The agent is registered through `SMAppService` from a plist **inside** the bundle
/// (`Contents/Library/LaunchAgents/`). Writing a plist into `~/Library/LaunchAgents`
/// pointing at `…/Contents/MacOS/AlejoVoice` also works, but then macOS attributes the
/// job to a bare executable: Login Items / Background Activity shows a generic "exec"
/// icon with no app name. Registered from the bundle, it shows the app.
enum LoginAgent {
    static let label = "com.alejo.alejovoice"

    /// Legacy location used before the switch to SMAppService.
    private static var legacyPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func ensureInstalled() {
        // Only manage the agent for a real install: never point it at a DMG volume or
        // at a build directory.
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }

        removeLegacyAgent()

        let service = SMAppService.agent(plistName: "\(label).plist")
        switch service.status {
        case .enabled:
            return
        case .requiresApproval:
            NSLog("AlejoVoice: login agent needs approval in System Settings → Login Items")
            return
        default:
            do {
                try service.register()
            } catch {
                NSLog("AlejoVoice: could not register login agent — \(error.localizedDescription)")
            }
        }
    }

    static func remove() {
        removeLegacyAgent()
        try? SMAppService.agent(plistName: "\(label).plist").unregister()
    }

    /// A stale user-domain agent would launch a second copy alongside the registered one.
    private static func removeLegacyAgent() {
        guard FileManager.default.fileExists(atPath: legacyPlistURL.path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: legacyPlistURL)
    }
}
