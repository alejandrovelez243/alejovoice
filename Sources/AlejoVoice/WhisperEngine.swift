import Foundation
import CWhisper

/// In-process whisper.cpp: model loads once, transcriptions run on a serial queue
/// (results arrive in submission order).
final class WhisperEngine {
    static let shared = WhisperEngine()

    private var ctx: OpaquePointer?
    private let queue = DispatchQueue(label: "alejovoice.whisper", qos: .userInitiated)
    private(set) var isLoaded = false

    private var warmedUp = false

    func preload(completion: ((Bool) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            let ok = self.loadIfNeeded()
            if ok, !self.warmedUp, let ctx = self.ctx {
                // Tiny silent inference so Metal kernels compile before the first real segment.
                self.warmedUp = true
                var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                params.print_progress = false
                params.print_realtime = false
                params.no_timestamps = true
                params.n_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount - 2))
                let silence = [Float](repeating: 0, count: 16000)
                _ = Self.run(ctx: ctx, params: params, samples: silence)
            }
            if let completion {
                DispatchQueue.main.async { completion(ok) }
            }
        }
    }

    private func loadIfNeeded() -> Bool {
        if ctx != nil { return true }
        guard ModelManager.isModelInstalled else { return false }
        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = true
        ctx = whisper_init_from_file_with_params(ModelManager.modelPath.path, params)
        isLoaded = ctx != nil
        return isLoaded
    }

    /// Transcribes 16 kHz mono Float32 samples. `prompt` carries previous text for continuity.
    func transcribe(samples: [Float], prompt: String?,
                    completion: @escaping (String) -> Void) {
        queue.async { [weak self] in
            guard let self, self.loadIfNeeded(), let ctx = self.ctx, samples.count > 1600 else {
                DispatchQueue.main.async { completion("") }
                return
            }

            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.print_progress = false
            params.print_realtime = false
            params.print_special = false
            params.print_timestamps = false
            params.translate = false
            params.no_timestamps = true
            params.suppress_blank = true
            params.n_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount - 2))

            let language = AppSettings.language
            let text: String = language.withCString { langPtr in
                params.language = language == "auto" ? nil : langPtr
                if let prompt, !prompt.isEmpty {
                    return prompt.withCString { promptPtr in
                        params.initial_prompt = promptPtr
                        return Self.run(ctx: ctx, params: params, samples: samples)
                    }
                }
                return Self.run(ctx: ctx, params: params, samples: samples)
            }
            DispatchQueue.main.async { completion(text) }
        }
    }

    private static func run(ctx: OpaquePointer, params: whisper_full_params, samples: [Float]) -> String {
        let status = samples.withUnsafeBufferPointer { buf in
            whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
        }
        guard status == 0 else { return "" }
        var out = ""
        for i in 0..<whisper_full_n_segments(ctx) {
            if let cstr = whisper_full_get_segment_text(ctx, i) {
                out += String(cString: cstr)
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
