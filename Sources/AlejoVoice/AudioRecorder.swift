import AVFoundation

/// Streams microphone input as 16 kHz mono Float32 chunks with live levels.
final class AudioRecorder {
    /// Called on the main queue with each converted chunk and its RMS level.
    var onChunk: (([Float], Float) -> Void)?
    /// Called on the main queue when the audio device changes mid-recording.
    var onDeviceChange: (() -> Void)?

    private var engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var configObserver: NSObjectProtocol?
    private(set) var isRecording = false

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    static func requestPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    func start() throws {
        guard !isRecording else { return }

        // A reused engine whose input device changed (headphones plugged in, device
        // gone to sleep) reports an invalid format, and installTap then raises an
        // ObjC exception that Swift cannot catch — the process aborts. So: always
        // start from a fresh engine, and never install a tap with a format CoreAudio
        // would reject.
        rebuildEngine()
        var inputFormat = engine.inputNode.outputFormat(forBus: 0)
        if !Self.isUsable(inputFormat) {
            // The first query right after a device switch can come back as 0 Hz /
            // 0 channels; a second engine usually sees the settled device.
            rebuildEngine()
            inputFormat = engine.inputNode.outputFormat(forBus: 0)
        }
        guard Self.isUsable(inputFormat) else {
            throw NSError(domain: "AlejoVoice", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No hay micrófono disponible"])
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "AlejoVoice", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Formato de micrófono no soportado"])
        }
        self.converter = converter

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer, inputFormat: inputFormat)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            isRecording = false
            throw error
        }
        isRecording = true
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        teardownEngine()
    }

    // MARK: - Engine lifecycle

    private func rebuildEngine() {
        teardownEngine()
        engine = AVAudioEngine()
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isRecording else { return }
            // Device swapped while recording: finalize instead of feeding the
            // converter buffers in a format it was not built for.
            self.stop()
            self.onDeviceChange?()
        }
    }

    private func teardownEngine() {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        converter = nil
    }

    private static func isUsable(_ format: AVAudioFormat) -> Bool {
        format.sampleRate > 0 && format.channelCount > 0
    }

    // MARK: - Conversion

    private func process(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        guard let converter, isRecording else { return }
        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        converter.convert(to: out, error: nil) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }

        let n = Int(out.frameLength)
        guard n > 0, let ch = out.floatChannelData?[0] else { return }
        let chunk = Array(UnsafeBufferPointer(start: ch, count: n))
        var sum: Float = 0
        for s in chunk { sum += s * s }
        let rms = sqrtf(sum / Float(n))
        DispatchQueue.main.async { [weak self] in self?.onChunk?(chunk, rms) }
    }
}
