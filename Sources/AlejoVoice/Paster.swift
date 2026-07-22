import AppKit
import Carbon.HIToolbox

/// Puts text on the pasteboard and synthesizes Cmd+V into the frontmost app.
enum Paster {
    /// Returns false when the paste keystroke could not be sent (no Accessibility
    /// permission) — the text is still left on the clipboard as a fallback.
    @discardableResult
    static func paste(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard AXIsProcessTrusted() else { return false }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            sendCmdV()
            // Restore the user's clipboard once the target app has consumed the paste.
            if let previous {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
        return true
    }

    private static func sendCmdV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKey = CGKeyCode(kVK_ANSI_V)
        let cmdKey = CGKeyCode(kVK_Command)

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)

        cmdDown?.flags = .maskCommand
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand

        for event in [cmdDown, vDown, vUp, cmdUp] {
            event?.post(tap: .cgSessionEventTap)
        }
    }
}
