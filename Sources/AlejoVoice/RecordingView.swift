import SwiftUI

enum PanelState: Equatable {
    case downloading(Double)
    case listening
    case transcribing
    case error(String)
}

final class PanelModel: ObservableObject {
    @Published var state: PanelState = .listening
    @Published var level: Float = 0          // smoothed 0…1
    @Published var partialText: String = ""

    private var smoothed: Float = 0

    func push(level raw: Float) {
        let target = min(1, raw * 10)
        smoothed = target > smoothed
            ? smoothed + (target - smoothed) * 0.6
            : smoothed + (target - smoothed) * 0.15
        level = smoothed
    }

    func reset() {
        smoothed = 0
        level = 0
        partialText = ""
    }
}

/// AlejoVoice identity: a dark glass sphere with an emerald aurora swirling
/// inside and a thin ring that pulses with the voice. Two-color world
/// (emerald → cyan) — deliberately not Siri's rainbow.
struct OrbView: View {
    @ObservedObject var model: PanelModel
    var onStop: () -> Void
    var onCancel: () -> Void

    @State private var spin = false
    @State private var hovering = false

    private let emerald = Color(red: 0.18, green: 0.90, blue: 0.62)
    private let cyan = Color(red: 0.10, green: 0.75, blue: 0.85)
    private let deepGreen = Color(red: 0.02, green: 0.16, blue: 0.11)

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                sphere
                    .frame(width: 116, height: 116)
                    .contentShape(Circle())
                    .onTapGesture { onStop() }

                if hovering {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                }
            }
            caption
        }
        .padding(.top, 14)
        .frame(width: 260, height: 220, alignment: .top)
        .onHover { hovering = $0 }
        .onAppear { spin = true }
    }

    // MARK: - Sphere

    @ViewBuilder
    private var sphere: some View {
        let pulse = CGFloat(model.level)
        ZStack {
            // Voice ring: thin, breathes outward with the level.
            Circle()
                .stroke(emerald.opacity(0.35 + Double(pulse) * 0.45), lineWidth: 1.5)
                .scaleEffect(1.10 + pulse * 0.18)

            // Sphere body: dark glass base.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [deepGreen, Color(red: 0.01, green: 0.05, blue: 0.04)],
                        center: .init(x: 0.4, y: 0.35),
                        startRadius: 6, endRadius: 70
                    )
                )

            // Aurora swirling inside the glass.
            AngularGradient(
                colors: [emerald.opacity(0.85), cyan.opacity(0.25),
                         emerald.opacity(0.10), cyan.opacity(0.7),
                         emerald.opacity(0.85)],
                center: .init(x: 0.5, y: 0.62)
            )
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: rotationDuration).repeatForever(autoreverses: false),
                       value: spin)
            .blur(radius: 14)
            .opacity(0.55 + Double(pulse) * 0.45)
            .clipShape(Circle())

            // Bottom glow that answers the voice.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [emerald.opacity(0.35 + Double(pulse) * 0.4), .clear],
                        center: .init(x: 0.5, y: 0.85),
                        startRadius: 2, endRadius: 60
                    )
                )

            // Specular highlight = glass.
            Ellipse()
                .fill(
                    LinearGradient(colors: [.white.opacity(0.35), .clear],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 62, height: 30)
                .offset(x: -14, y: -36)
                .blur(radius: 3)

            // Crisp rim.
            Circle()
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.25), emerald.opacity(0.15)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )

            stateOverlay
        }
        .scaleEffect(1 + pulse * 0.06)
        .animation(.easeOut(duration: 0.1), value: model.level)
    }

    private var rotationDuration: Double {
        switch model.state {
        case .transcribing: return 1.6
        default: return 7
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch model.state {
        case .downloading(let progress):
            Circle()
                .trim(from: 0, to: progress)
                .stroke(emerald, style: .init(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 92, height: 92)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.95))
        default:
            EmptyView()
        }
    }

    // MARK: - Caption

    @ViewBuilder
    private var caption: some View {
        VStack(spacing: 5) {
            Text(captionTitle)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.95))

            if case .listening = model.state, !model.partialText.isEmpty {
                Text(model.partialText.suffix(90))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 220)
            }
            if case .error(let message) = model.state {
                Text(message)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 220)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            // Plain translucent fill — NSVisualEffectView materials force an
            // opaque window backdrop, which killed the transparency.
            Capsule(style: .continuous)
                .fill(Color(red: 0.03, green: 0.07, blue: 0.05).opacity(0.88))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    private var captionTitle: String {
        switch model.state {
        case .downloading(let p): return "Descargando modelo… \(Int(p * 100))%"
        case .listening: return "Escuchando…"
        case .transcribing: return "Un momento…"
        case .error: return "Ups"
        }
    }
}
