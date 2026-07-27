import AppKit

/// In-app updater: reads the latest GitHub release, downloads its zip, swaps the
/// installed bundle and relaunches. The DMG is only ever needed for the first
/// install — after that this replaces the app in place, so macOS keeps the
/// Microphone/Accessibility grants and no second copy is ever created.
@MainActor
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    static let repository = "alejandrovelez243/alejovoice"
    private static let label = "com.alejo.alejovoice"

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case downloading(Double)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private var pendingVersion: String?
    private var pendingURL: URL?
    private var session: URLSession?

    // MARK: - Check

    func check() {
        guard state != .checking, !isBusy else { return }
        state = .checking

        var request = URLRequest(url: URL(string:
            "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("AlejoVoice/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.state = .failed("Sin conexión: \(error.localizedDescription)")
                    return
                }
                guard let code = (response as? HTTPURLResponse)?.statusCode, code == 200,
                      let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.state = .failed("GitHub no devolvió ninguna versión publicada.")
                    return
                }
                let tag = (json["tag_name"] as? String) ?? ""
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let assets = (json["assets"] as? [[String: Any]]) ?? []
                let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }

                guard !latest.isEmpty else {
                    self.state = .failed("Release sin número de versión.")
                    return
                }
                guard Self.isNewer(latest, than: self.currentVersion) else {
                    self.state = .upToDate
                    return
                }
                guard let urlString = zip?["browser_download_url"] as? String,
                      let url = URL(string: urlString) else {
                    self.state = .failed("La versión \(latest) no incluye un .zip de actualización.")
                    return
                }
                self.pendingVersion = latest
                self.pendingURL = url
                self.state = .available(version: latest)
            }
        }.resume()
    }

    /// Compares dotted numeric versions ("1.10.0" > "1.9.3").
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let l = i < a.count ? a[i] : 0
            let r = i < b.count ? b[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: - Download + install

    func install() {
        guard let url = pendingURL, !isBusy else { return }
        guard Self.canReplaceBundle else {
            state = .failed("No se puede escribir en \(Bundle.main.bundlePath). Instala con el DMG.")
            return
        }
        state = .downloading(0)
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        self.session = session
        session.downloadTask(with: url).resume()
    }

    private var isBusy: Bool {
        switch state {
        case .downloading, .installing: return true
        default: return false
        }
    }

    private static var canReplaceBundle: Bool {
        let path = Bundle.main.bundlePath
        return !path.hasPrefix("/Volumes/")
            && FileManager.default.isWritableFile(atPath: (path as NSString).deletingLastPathComponent)
    }

    /// Unpacks the zip, sanity-checks the new bundle, then hands the swap to a
    /// detached shell script — the app cannot overwrite itself while running.
    private func finishInstall(zip: URL) {
        state = .installing
        let target = Bundle.main.bundlePath
        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AlejoVoiceUpdate-\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path])

            let contents = try FileManager.default.contentsOfDirectory(atPath: staging.path)
            guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
                throw UpdateError("El zip no contiene una app.")
            }
            let newApp = staging.appendingPathComponent(appName)

            // Refuse anything that is not a valid, correctly-identified AlejoVoice.
            try Self.run("/usr/bin/codesign", ["--verify", "--deep", newApp.path])
            let plist = newApp.appendingPathComponent("Contents/Info.plist")
            guard let info = NSDictionary(contentsOf: plist) as? [String: Any],
                  info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
                throw UpdateError("La app descargada no es AlejoVoice.")
            }

            let script = staging.appendingPathComponent("swap.sh")
            try Self.swapScript(newApp: newApp.path, target: target, staging: staging.path)
                .write(to: script, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script.path]
            try process.run()

            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            state = .failed(error.localizedDescription)
        }
    }

    private static func swapScript(newApp: String, target: String, staging: String) -> String {
        """
        #!/bin/sh
        # Waits for AlejoVoice to exit, replaces the bundle in place, relaunches it.
        pid=\(ProcessInfo.processInfo.processIdentifier)
        i=0
        while kill -0 "$pid" 2>/dev/null && [ $i -lt 100 ]; do
          sleep 0.2
          i=$((i + 1))
        done
        /usr/bin/rsync -a --delete "\(newApp)/" "\(target)/"
        agent="$HOME/Library/LaunchAgents/\(label).plist"
        if [ -f "$agent" ]; then
          /bin/launchctl kickstart -k "gui/$(id -u)/\(label)" || /usr/bin/open "\(target)"
        else
          /usr/bin/open "\(target)"
        fi
        rm -rf "\(staging)"
        """
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError("\((tool as NSString).lastPathComponent) falló (código \(process.terminationStatus)).")
        }
    }

    private struct UpdateError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

extension Updater: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                               didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                               totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in self.state = .downloading(progress) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                               didFinishDownloadingTo location: URL) {
        // The temp file is deleted when this returns, so move it first.
        let kept = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AlejoVoice-\(UUID().uuidString).zip")
        try? FileManager.default.moveItem(at: location, to: kept)
        Task { @MainActor in self.finishInstall(zip: kept) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                               didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            self.state = .failed("Descarga fallida: \(error.localizedDescription)")
            self.session?.invalidateAndCancel()
            self.session = nil
        }
    }
}
