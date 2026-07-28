import Foundation

/// Streaming dictation: cuts audio into segments at short pauses and transcribes
/// them while the user keeps talking; auto-stops after a long silence.
final class DictationController {
    // Tunables (seconds).
    private let segmentPause: Double = 0.8      // pause that closes a segment
    private let autoStopSilence: Double = 2.5   // silence that ends the dictation
    private let noSpeechTimeout: Double = 8.0   // never spoke → cancel
    private let minSegmentSpeech: Double = 0.3  // ignore segments with less speech
    private let speechThreshold: Float = 0.015  // RMS gate

    var onLevel: ((Float) -> Void)?
    var onPartialText: ((String) -> Void)?
    var onFinished: ((String) -> Void)?         // final text ("" if nothing)

    private let recorder = AudioRecorder()
    private var segment: [Float] = []
    private var parts: [Int: String] = [:]
    private var nextIndex = 0
    private var pendingCount = 0
    private var finishing = false
    private(set) var isActive = false

    private var recordedTime: Double = 0
    private var lastSpeechTime: Double = 0
    private var speechInSegment: Double = 0
    private var spokeAtAll = false

    init() {
        recorder.onChunk = { [weak self] chunk, rms in
            self?.handle(chunk: chunk, rms: rms)
        }
        recorder.onDeviceChange = { [weak self] in
            // Headphones plugged in / device switched mid-dictation: deliver what we
            // already captured instead of leaving the session hanging.
            guard let self, self.isActive else { return }
            Log.write("device change → finishing at t=\(self.recordedTime)")
            self.finishNow()
        }
    }

    func start() throws {
        segment.removeAll()
        parts.removeAll()
        nextIndex = 0
        pendingCount = 0
        finishing = false
        recordedTime = 0
        lastSpeechTime = 0
        speechInSegment = 0
        spokeAtAll = false
        try recorder.start()
        isActive = true
    }

    /// User asked to stop (hotkey/click): finalize with whatever we have.
    func finish() {
        guard isActive, !finishing else { return }
        finishing = true
        recorder.stop()
        isActive = false
        closeSegment()
        checkDone()
    }

    func cancel() {
        recorder.stop()
        isActive = false
        finishing = false
        segment.removeAll()
        parts.removeAll()
    }

    // MARK: - Audio handling

    private func handle(chunk: [Float], rms: Float) {
        guard isActive else { return }
        onLevel?(rms)

        let dt = Double(chunk.count) / 16000.0
        recordedTime += dt
        segment.append(contentsOf: chunk)

        if rms > speechThreshold {
            lastSpeechTime = recordedTime
            speechInSegment += dt
            spokeAtAll = true
        }

        let silence = recordedTime - lastSpeechTime

        if !spokeAtAll {
            if recordedTime > noSpeechTimeout { finishNow() }
            return
        }

        if silence > autoStopSilence {
            finishNow()
        } else if silence > segmentPause, speechInSegment > minSegmentSpeech {
            closeSegment()
        }
    }

    private func finishNow() {
        Log.write("finishNow t=\(recordedTime) spoke=\(spokeAtAll) segments=\(nextIndex)")
        finishing = true
        recorder.stop()
        isActive = false
        closeSegment()
        checkDone()
    }

    // MARK: - Segments

    private func closeSegment() {
        let samples = segment
        segment.removeAll()
        let hadSpeech = speechInSegment > minSegmentSpeech
        speechInSegment = 0
        guard hadSpeech, samples.count > 1600 else { return }

        let index = nextIndex
        nextIndex += 1
        pendingCount += 1
        let prompt = orderedText()

        WhisperEngine.shared.transcribe(samples: samples, prompt: prompt) { [weak self] text in
            guard let self else { return }
            self.parts[index] = text
            self.pendingCount -= 1
            self.onPartialText?(self.orderedText())
            self.checkDone()
        }
    }

    private func orderedText() -> String {
        parts.sorted { $0.key < $1.key }
            .map(\.value)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func checkDone() {
        guard finishing, pendingCount == 0 else { return }
        finishing = false
        onFinished?(orderedText())
    }
}
