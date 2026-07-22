import AppKit
import SwiftUI

/// Floating, non-activating, transparent panel — only the orb and caption are visible.
final class RecordingPanel: NSPanel {
    init(model: PanelModel, onStop: @escaping () -> Void, onCancel: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 210),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        ignoresMouseEvents = false

        let view = OrbView(model: model, onStop: onStop, onCancel: onCancel)
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        contentView = hosting
    }

    func showCentered() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.midX - 130
        let y = frame.minY + frame.height * 0.16
        setFrameOrigin(NSPoint(x: x, y: y))
        orderFrontRegardless()
    }
}
