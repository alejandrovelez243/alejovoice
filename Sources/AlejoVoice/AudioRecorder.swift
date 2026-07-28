import AVFoundation

/// Streams microphone input as 16 kHz mono Float32 chunks with live levels.
final class AudioRecorder {
    /// Called on the main queue with each converted chunk and its RMS level.
    var onChunk: (([Float], Float) -> Void)?
    /// Called on the main queue when the audio device changes mid-recording.
    var onDeviceChange: (() -> Void)?

    // Kept nil while idle on purpose. An AVAudioEngine whose inputNode has been
    // touched holds the HAL input device open, which macOS surfaces as the orange
    // "app is using the microphone" indicator — even with the engine stopped. The
    // only way to release it is to drop the engine entirely between dictations.
    private var engine: AVAudioEngine?
    private var tappedInput: AVAudioInputNode?
    private var converter: AVAudioConverter?
    private var configObserver: NSObjectProtocol?
    private var chunkCount = 0
    private var restartsLeft = 0
    private(set) var isRecording = false

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    static func requestPermission(_ completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        Log.write("mic authorizationStatus=\(status.rawValue)")
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            Log.write("requesting microphone access")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Log.write("microphone request returned granted=\(granted)")
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    func start() throws {
        guard !isRecording else { return }
        restartsLeft = 3
        chunkCount = 0
        try startEngine()
        isRecording = true
    }

    private func startEngine() throws {
        // A reused engine whose input device changed (headphones plugged in, device
        // gone to sleep) reports an invalid format, and installTap then raises an
        // ObjC exception that Swift cannot catch — the process aborts. So: always
        // start from a fresh engine, and never install a tap with a format CoreAudio
        // would reject.
        var engine = rebuildEngine()
        var input = engine.inputNode
        Self.applyPreferredDevice(to: input)
        var inputFormat = input.outputFormat(forBus: 0)
        if !Self.isUsable(inputFormat) {
            // The first query right after a device switch can come back as 0 Hz /
            // 0 channels; a second engine usually sees the settled device.
            engine = rebuildEngine()
            input = engine.inputNode
            Self.applyPreferredDevice(to: input)
            inputFormat = input.outputFormat(forBus: 0)
        }
        guard Self.isUsable(inputFormat) else {
            teardownEngine()
            throw NSError(domain: "AlejoVoice", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No hay micrófono disponible"])
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            teardownEngine()
            throw NSError(domain: "AlejoVoice", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Formato de micrófono no soportado"])
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer, inputFormat: inputFormat)
        }
        tappedInput = input
        engine.prepare()
        do {
            try engine.start()
        } catch {
            Log.write("recorder engine.start failed: \(error.localizedDescription)")
            teardownEngine()
            throw error
        }
        Log.write("recorder started sr=\(inputFormat.sampleRate) ch=\(inputFormat.channelCount)")
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        Log.write("recorder stopped chunks=\(chunkCount)")
        teardownEngine()
    }

    // MARK: - Engine lifecycle

    @discardableResult
    private func rebuildEngine() -> AVAudioEngine {
        teardownEngine()
        let engine = AVAudioEngine()
        self.engine = engine
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.handleConfigChange()
        }
        return engine
    }

    /// Bluetooth headsets (AirPods) switch the input device the moment the mic is
    /// opened, so the very first thing a fresh engine sees is a configuration change,
    /// ~80 ms in and before a single buffer arrives. Treating that as "device swapped,
    /// finalize" killed every dictation with headphones on. Nothing has been captured
    /// yet at that point, so the right move is to rebuild onto the settled device.
    /// Only a change that arrives after audio started flowing ends the dictation.
    private func handleConfigChange() {
        Log.write("audio config change after \(chunkCount) chunks, restartsLeft=\(restartsLeft)")
        guard chunkCount == 0, restartsLeft > 0 else {
            isRecording = false
            teardownEngine()
            onDeviceChange?()
            return
        }
        restartsLeft -= 1
        teardownEngine()
        // Let CoreAudio finish the switch before asking for the new device.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.isRecording else { return }
            do {
                try self.startEngine()
            } catch {
                Log.write("restart after config change failed: \(error.localizedDescription)")
                self.isRecording = false
                self.teardownEngine()
                self.onDeviceChange?()
            }
        }
    }

    private func teardownEngine() {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        // Only ever touch the input node we already instantiated: asking a fresh
        // engine for `inputNode` just to remove a tap would open the mic again.
        tappedInput?.removeTap(onBus: 0)
        tappedInput = nil
        if let engine {
            if engine.isRunning { engine.stop() }
            engine.reset()
        }
        engine = nil
        converter = nil
    }

    /// Points the engine's HAL unit at the microphone chosen in Ajustes. Must run
    /// before `outputFormat(forBus:)` is read and before the tap is installed —
    /// switching the device afterwards invalidates both.
    private static func applyPreferredDevice(to input: AVAudioInputNode) {
        guard let uid = AppSettings.inputDeviceUID else { return }
        guard let unit = input.audioUnit else { return }
        guard var deviceID = AudioDevices.deviceID(forUID: uid) else {
            // Chosen mic is unplugged: fall back to the system default rather than
            // failing to record at all.
            Log.write("preferred input \(uid) not present — using system default")
            return
        }
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        Log.write("input device set uid=\(uid) id=\(deviceID) status=\(status)")
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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.chunkCount += 1
            if self.chunkCount == 1 { Log.write("first chunk rms=\(rms)") }
            self.onChunk?(chunk, rms)
        }
    }
}
