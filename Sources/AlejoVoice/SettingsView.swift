import SwiftUI

struct SettingsView: View {
    @State private var hotkey: HotkeyChoice = AppSettings.hotkey
    @State private var language: String = AppSettings.language
    @ObservedObject private var updater = Updater.shared

    private let languages: [(code: String, name: String)] = [
        ("auto", "Automático"),
        ("es", "Español"),
        ("en", "English"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            }

            Text("Doble tap del atajo inicia la grabación; otro doble tap la termina y escribe el texto donde esté el cursor.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            updateSection
        }
        .padding(20)
        .frame(width: 400)
    }

    private var updateSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Versión \(updater.currentVersion)")
                    .font(.system(size: 13, weight: .medium))
                statusLine
            }
            Spacer(minLength: 8)
            actionButton
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch updater.state {
        case .idle:
            caption("Actualiza sin reinstalar: reemplaza la app en sitio y conserva los permisos.")
        case .checking:
            Label("Buscando…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption).foregroundColor(.secondary)
        case .upToDate:
            Label("Ya tienes la última versión", systemImage: "checkmark.circle")
                .font(.caption).foregroundColor(.secondary)
        case .available(let version):
            Label("Versión \(version) disponible", systemImage: "arrow.down.circle")
                .font(.caption).foregroundColor(.accentColor)
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 4) {
                Text("Descargando… \(Int(progress * 100))%")
                    .font(.caption).foregroundColor(.secondary)
                ProgressView(value: progress).frame(width: 200)
            }
        case .installing:
            Label("Instalando y reiniciando…", systemImage: "gearshape")
                .font(.caption).foregroundColor(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch updater.state {
        case .available:
            Button("Actualizar ahora") { updater.install() }
                .keyboardShortcut(.defaultAction)
        case .checking, .downloading, .installing:
            ProgressView().controlSize(.small)
        default:
            Button("Buscar actualizaciones") { updater.check() }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
