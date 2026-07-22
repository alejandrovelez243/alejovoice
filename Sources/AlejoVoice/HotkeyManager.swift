import AppKit

/// Detects a double-tap of a modifier key (e.g. right Command) system-wide.
final class HotkeyManager {
    var onDoubleTap: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastTapTime: TimeInterval = 0
    private let doubleTapWindow: TimeInterval = 0.4

    func start() {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    private func handle(_ event: NSEvent) {
        let target = AppSettings.hotkey
        guard event.keyCode == target.keyCode else {
            lastTapTime = 0
            return
        }
        // Only count the key-down transition (modifier flag present).
        let isDown: Bool
        switch target {
        case .rightCommand: isDown = event.modifierFlags.contains(.command)
        case .rightOption: isDown = event.modifierFlags.contains(.option)
        case .leftControl: isDown = event.modifierFlags.contains(.control)
        }
        guard isDown else { return }

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastTapTime < doubleTapWindow {
            lastTapTime = 0
            DispatchQueue.main.async { self.onDoubleTap?() }
        } else {
            lastTapTime = now
        }
    }
}
