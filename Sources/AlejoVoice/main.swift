import AppKit
import AVFoundation
import ServiceManagement

// Hidden diagnostics: AlejoVoice --diagnose prints the TCC state of THIS process.
// Careful: run from a terminal, macOS attributes permissions to the responsible process
// (the terminal app), so the numbers describe the terminal, not AlejoVoice. The settings
// window shows the app's own state — trust that one.
if CommandLine.arguments.contains("--diagnose") {
    let mic: String
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: mic = "authorized"
    case .denied: mic = "denied"
    case .restricted: mic = "restricted"
    case .notDetermined: mic = "notDetermined"
    @unknown default: mic = "unknown"
    }
    print("bundle:        \(Bundle.main.bundlePath)")
    print("version:       \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?")")
    print("bundle id:     \(Bundle.main.bundleIdentifier ?? "nil")")
    print("accessibility: \(AXIsProcessTrusted() ? "trusted" : "NOT trusted")")
    print("microphone:    \(mic)")
    print("model:         \(ModelManager.isModelInstalled ? "installed" : "missing")")
    exit(0)
}

// Hidden cleanup: AlejoVoice --unregister-agent drops the old KeepAlive LaunchAgent
// registration from macOS's background-item database. Needed once on machines that ran a
// version which shipped Contents/Library/LaunchAgents.
if CommandLine.arguments.contains("--unregister-agent") {
    let agent = SMAppService.agent(plistName: "com.alejo.alejovoice.plist")
    print("status before: \(agent.status.rawValue)")
    do {
        try agent.unregister()
        print("unregistered")
    } catch {
        print("unregister failed: \(error.localizedDescription)")
    }
    exit(0)
}

// Hidden: AlejoVoice --request-mic forces the microphone prompt and reports the answer.
if CommandLine.arguments.contains("--request-mic") {
    AudioRecorder.requestPermission { granted in
        print(granted ? "microphone granted" : "microphone denied")
        exit(granted ? 0 : 1)
    }
    RunLoop.main.run()
}

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
