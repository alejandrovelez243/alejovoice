import SwiftUI
import AVFoundation
import ApplicationServices

struct SettingsView: View {
    @State private var hotkey: HotkeyChoice = AppSettings.hotkey
    @State private var language: String = AppSettings.language
    @State private var inputDevice: String = AppSettings.inputDeviceUID ?? ""
    @State private var inputDevices: [AudioDevices.Device] = AudioDevices.inputs()
    @ObservedObject private var updater = Updater.shared
    @StateObject private var permissions = PermissionState()
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

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

                Picker("Micrófono", selection: $inputDevice) {
                    Text("Predeterminado del sistema").tag("")
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .onChange(of: inputDevice) {
                    AppSettings.inputDeviceUID = $0.isEmpty ? nil : $0
                }
            }

            Text("Doble tap del atajo inicia la grabación; otro doble tap la termina y escribe el texto donde esté el cursor.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            permissionsSection

            Divider()

            updateSection
        }
        .padding(20)
        .frame(width: 400)
        .onReceive(timer) { _ in
            permissions.refresh()
            // Devices come and go (headphones, docks) while this window is open.
            let current = AudioDevices.inputs()
            if current != inputDevices { inputDevices = current }
        }
    }

    // MARK: - Permissions
    //
    // Shown here because this is the only place the state can be read truthfully: a
    // CLI check run from a terminal reports the *terminal's* TCC decisions (macOS
    // attributes the request to the responsible process), not the app's.

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permisos")
                .font(.system(size: 13, weight: .medium))
            permissionRow(
                title: "Micrófono",
                detail: "para grabar tu voz",
                granted: permissions.microphone,
                pane: "Privacy_Microphone"
            )
            permissionRow(
                title: "Accesibilidad",
                detail: "atajo global y escritura del texto",
                granted: permissions.accessibility,
                pane: "Privacy_Accessibility"
            )
        }
    }

    private func permissionRow(title: String, detail: String,
                               granted: Bool, pane: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption)
                Text(detail).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if !granted {
                Button("Abrir ajustes") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                }
                .controlSize(.small)
            }
        }
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

/// Live permission state for the settings window. Polled, because macOS sends no
/// notification when the user flips a toggle in System Settings.
final class PermissionState: ObservableObject {
    @Published var microphone = false
    @Published var accessibility = false

    init() { refresh() }

    func refresh() {
        microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibility = AXIsProcessTrusted()
    }
}
