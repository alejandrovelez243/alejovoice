import AppKit

// Hidden smoke-test mode: AlejoVoice --transcribe file.wav (16 kHz mono 16-bit).
if let idx = CommandLine.arguments.firstIndex(of: "--transcribe"),
   CommandLine.arguments.count > idx + 1 {
    let url = URL(fileURLWithPath: CommandLine.arguments[idx + 1])
    guard let data = try? Data(contentsOf: url), data.count > 44 else {
        print("no wav"); exit(1)
    }
    let pcm = data.dropFirst(44)
    var samples = [Float](repeating: 0, count: pcm.count / 2)
    pcm.withUnsafeBytes { raw in
        let int16 = raw.bindMemory(to: Int16.self)
        for i in 0..<samples.count { samples[i] = Float(Int16(littleEndian: int16[i])) / 32768 }
    }
    let start = Date()
    WhisperEngine.shared.preload { ok in
        guard ok else { print("model load failed"); exit(1) }
        print("model loaded in \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
        let t0 = Date()
        WhisperEngine.shared.transcribe(samples: samples, prompt: nil) { text in
            print("transcribed in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s: \(text)")
            exit(0)
        }
    }
    RunLoop.main.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
