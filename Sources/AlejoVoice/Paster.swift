import AppKit
import ApplicationServices

/// Inserts text into the frontmost app without touching the clipboard.
///
/// Order of attempts:
///   1. Accessibility text insertion (instant, works in native text fields).
///   2. Synthesized Unicode keystrokes (works anywhere that accepts typing).
///   3. Clipboard — only when Accessibility permission is missing, so there is no
///      other way to deliver the text.
enum Paster {
    enum Outcome {
        case inserted    // written straight into the focused text element
        case typed       // delivered as synthetic keystrokes
        case clipboard   // fallback: left on the clipboard for the user to paste
    }

    /// Delay before delivering: the hotkey modifier the user just double-tapped has
    /// to be physically released first, otherwise keystrokes turn into shortcuts.
    private static let deliveryDelay: TimeInterval = 0.12
    private static let typeQueue = DispatchQueue(label: "alejovoice.typing", qos: .userInitiated)

    @discardableResult
    static func insert(_ text: String) -> Outcome {
        guard !text.isEmpty else { return .inserted }

        guard AXIsProcessTrusted() else {
            copyToClipboard(text)
            return .clipboard
        }

        if insertViaAccessibility(text) { return .inserted }

        typeQueue.asyncAfter(deadline: .now() + deliveryDelay) {
            typeUnicode(text)
        }
        return .typed
    }

    // MARK: - Accessibility insertion

    /// Writes into the focused element's selected-text range (replacing the selection,
    /// or inserting at the caret when nothing is selected). Returns false when the
    /// element is not a writable text area or silently ignored the write.
    private static func insertViaAccessibility(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return false }
        let element = focusedRef as! AXUIElement

        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }

        // Some apps (web views, Electron editors) report the attribute as settable and
        // then drop the write, which would silently swallow the dictation. Only trust
        // this path when the value can be read back and actually changed; otherwise
        // fall through to typing, which works everywhere.
        guard let before = stringValue(of: element) else { return false }
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString,
                                           text as CFTypeRef) == .success else { return false }
        guard let after = stringValue(of: element), after != before else { return false }
        return true
    }

    private static func stringValue(of element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String, value.utf16.count < 200_000 else { return nil }
        return value
    }

    // MARK: - Synthetic typing

    /// Posts the text as Unicode key events — no clipboard involved. Runs on
    /// `typeQueue`; the small sleeps keep fast-refresh apps (Electron, terminals)
    /// from dropping characters.
    private static func typeUnicode(_ text: String) {
        // A private source starts with clean modifier state, so a Command key still
        // held down from the hotkey cannot turn the typed text into shortcuts.
        guard let source = CGEventSource(stateID: .privateState) else { return }

        for chunk in chunks(of: text, maxUTF16Units: 8) {
            var units = Array(chunk.utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
            down.flags = []
            up.flags = []
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
            usleep(1500)
        }
    }

    /// Splits on character boundaries so a chunk never cuts a surrogate pair or an
    /// emoji/accent cluster in half.
    private static func chunks(of text: String, maxUTF16Units: Int) -> [String] {
        var result: [String] = []
        var current = ""
        var units = 0
        for character in text {
            let size = String(character).utf16.count
            if units + size > maxUTF16Units, !current.isEmpty {
                result.append(current)
                current = ""
                units = 0
            }
            current.append(character)
            units += size
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: - Clipboard fallback

    private static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
