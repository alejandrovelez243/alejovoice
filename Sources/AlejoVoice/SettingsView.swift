import SwiftUI

struct SettingsView: View {
    @State private var hotkey: HotkeyChoice = AppSettings.hotkey
    @State private var language: String = AppSettings.language

    private let languages: [(code: String, name: String)] = [
        ("auto", "Automático"),
        ("es", "Español"),
        ("en", "English"),
    ]

    var body: some View {
        Form {
            Picker("Atajo global", selection: $hotkey) {
                ForEach(HotkeyChoice.allCases) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            .onChange(of: hotkey) { AppSettings.hotkey = $0 }

            Picker("Idioma", selection: $language) {
                ForEach(languages, id: \.code) { lang in
                    Text(lang.name).tag(lang.code)
                }
            }
            .onChange(of: language) { AppSettings.language = $0 }

            Text("Doble tap del atajo inicia la grabación; otro doble tap la termina y pega el texto donde esté el cursor.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 380)
    }
}
