import Foundation

/// Appends to ~/Library/Logs/AlejoVoice.log.
///
/// A file, not `NSLog`/`os_log`: the unified log is not readable with `log show` on this
/// system, which made permission problems impossible to diagnose from the outside.
enum Log {
    private static let queue = DispatchQueue(label: "alejovoice.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AlejoVoice.log")
    }

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            let url = fileURL
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
