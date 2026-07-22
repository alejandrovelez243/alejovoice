import Foundation

/// Downloads and locates the Whisper model in Application Support.
final class ModelManager: NSObject, URLSessionDownloadDelegate {
    static let shared = ModelManager()

    static let modelFileName = "ggml-large-v3-turbo-q5_0.bin"
    static let modelURL = URL(string:
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!

    var onProgress: ((Double) -> Void)?
    var onFinished: ((Result<URL, Error>) -> Void)?

    private var session: URLSession?

    static var modelsDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AlejoVoice/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var modelPath: URL { modelsDirectory.appendingPathComponent(modelFileName) }

    static var isModelInstalled: Bool {
        FileManager.default.fileExists(atPath: modelPath.path)
    }

    func download() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.session = session
        session.downloadTask(with: Self.modelURL).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            let dest = Self.modelPath
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
            onFinished?(.success(dest))
        } catch {
            onFinished?(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { onFinished?(.failure(error)) }
        self.session?.invalidateAndCancel()
        self.session = nil
    }
}
