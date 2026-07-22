import Foundation

enum HotkeyChoice: String, CaseIterable, Identifiable {
    case rightCommand
    case rightOption
    case leftControl

    var id: String { rawValue }

    var keyCode: UInt16 {
        switch self {
        case .rightCommand: return 54
        case .rightOption: return 61
        case .leftControl: return 59
        }
    }

    var displayName: String {
        switch self {
        case .rightCommand: return "Doble ⌘ derecho"
        case .rightOption: return "Doble ⌥ derecho"
        case .leftControl: return "Doble ⌃ izquierdo"
        }
    }
}

enum AppSettings {
    private static let hotkeyKey = "hotkeyChoice"
    private static let languageKey = "language"

    static var hotkey: HotkeyChoice {
        get {
            guard let raw = UserDefaults.standard.string(forKey: hotkeyKey),
                  let choice = HotkeyChoice(rawValue: raw) else { return .rightCommand }
            return choice
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: hotkeyKey) }
    }

    /// Whisper language code, "auto" for detection.
    static var language: String {
        get { UserDefaults.standard.string(forKey: languageKey) ?? "auto" }
        set { UserDefaults.standard.set(newValue, forKey: languageKey) }
    }
}
