import AppKit

/// Self-installed LaunchAgent: starts AlejoVoice at login and brings it back if it
/// ever crashes (`KeepAlive`/`SuccessfulExit=false` — quitting from the menu is a
/// clean exit, so it stays closed). Installed by the app itself so a plain
/// drag-from-DMG install gets it too, with no setup script.
enum LoginAgent {
    static let label = "com.alejo.alejovoice"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Writes (or rewrites, if the executable path changed) the agent and loads it.
    static func ensureInstalled() {
        let executable = Bundle.main.executablePath ?? ""
        // Only manage the agent for a real install: never point it at a DMG volume or
        // at a build directory.
        guard executable.hasPrefix("/Applications/") else { return }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
        ]

        let existing = NSDictionary(contentsOf: plistURL) as? [String: Any]
        let sameTarget = (existing?["ProgramArguments"] as? [String])?.first == executable
        if existing != nil, sameTarget { return }

        do {
            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            // bootout first so an older definition is replaced rather than duplicated;
            // this process keeps running either way.
            launchctl(["bootout", "gui/\(getuid())/\(label)"])
            launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
        } catch {
            NSLog("AlejoVoice: could not install login agent — \(error.localizedDescription)")
        }
    }

    static func remove() {
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
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
