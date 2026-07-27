// Draws the DMG installer window background — same dark-glass/emerald identity as
// the app icon and the in-app orb.
// Usage: swift scripts/make_dmg_background.swift <output.png> <width> <height> [version]
import AppKit

let args = CommandLine.arguments
let outputPath = args.count > 1 ? args[1] : "dmg_background.png"
let width = CGFloat(args.count > 2 ? Double(args[2]) ?? 640 : 640)
let height = CGFloat(args.count > 3 ? Double(args[3]) ?? 480 : 480)
let version = args.count > 4 ? args[4] : ""
// Everything is authored against a 640×480 reference layout and scaled from there,
// so the same code renders the @1x and @2x slices.
let s = width / 640

// Draw into an explicitly-sized bitmap: NSImage.lockFocus() would render at the main
// screen's backing scale, so on a Retina Mac the "640×420" slice came out 1280×840
// and tiffutil refused to pair it with the @2x one.
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width), pixelsHigh: Int(height),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }
let space = CGColorSpaceCreateDeviceRGB()

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

// Base: mid-tone teal. Finder paints the icon labels ("AlejoVoice", "Applications")
// black in light mode and white in dark mode, and that color cannot be set — so the
// background has to sit around 45–55% luminance for BOTH to stay readable. A
// near-black backdrop made the light-mode labels disappear.
let base = CGGradient(colorsSpace: space, colors: [
    rgb(0.44, 0.58, 0.55),
    rgb(0.28, 0.40, 0.38),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(base, start: CGPoint(x: width / 2, y: height),
                       end: CGPoint(x: width / 2, y: 0), options: [])

func glow(_ color: CGColor, at point: CGPoint, radius: CGFloat) {
    let clear = color.copy(alpha: 0)!
    let g = CGGradient(colorsSpace: space, colors: [color, clear] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: point, startRadius: 0,
                           endCenter: point, endRadius: radius, options: [])
}

// Aurora glows behind the two drop targets: emerald under the app, cool cyan under
// the Applications folder. They also lift the luminance right where the labels sit.
ctx.saveGState()
ctx.setBlendMode(.softLight)
glow(rgb(0.35, 1.0, 0.70, 0.45), at: CGPoint(x: 160 * s, y: height - 205 * s), radius: 260 * s)
glow(rgb(0.45, 0.92, 1.0, 0.30), at: CGPoint(x: 480 * s, y: height - 205 * s), radius: 250 * s)
glow(rgb(0.35, 1.0, 0.70, 0.30), at: CGPoint(x: 320 * s, y: height - 380 * s), radius: 200 * s)
ctx.restoreGState()

// Arrow from the app to the Applications folder: dashed track + solid head. Deep
// emerald, dark enough to read against the mid-tone base.
let emerald = rgb(0.04, 0.42, 0.30, 0.95)
let arrowY = height - 200 * s
ctx.saveGState()
ctx.setStrokeColor(emerald.copy(alpha: 0.45)!)
ctx.setLineWidth(2 * s)
ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [7 * s, 7 * s])
ctx.move(to: CGPoint(x: 268 * s, y: arrowY))
ctx.addLine(to: CGPoint(x: 358 * s, y: arrowY))
ctx.strokePath()
ctx.restoreGState()

ctx.saveGState()
ctx.setFillColor(emerald)
let tip = CGPoint(x: 384 * s, y: arrowY)
ctx.move(to: tip)
ctx.addLine(to: CGPoint(x: tip.x - 16 * s, y: arrowY + 9 * s))
ctx.addLine(to: CGPoint(x: tip.x - 16 * s, y: arrowY - 9 * s))
ctx.closePath()
ctx.fillPath()
ctx.restoreGState()

// Text.
func draw(_ text: String, size: CGFloat, weight: NSFont.Weight,
          color: NSColor, centerY: CGFloat, tracking: CGFloat = 0) {
    let font = NSFont.systemFont(ofSize: size * s, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: tracking * s,
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let bounds = string.size()
    string.draw(at: NSPoint(x: (width - bounds.width) / 2, y: height - centerY * s - bounds.height / 2))
}

// Dark ink on the mid-tone base — the same reason the base is mid-tone: it has to
// coexist with Finder's own black or white label text.
let ink = NSColor(calibratedRed: 0.05, green: 0.14, blue: 0.12, alpha: 1)
let inkSoft = NSColor(calibratedRed: 0.09, green: 0.22, blue: 0.19, alpha: 1)
let inkFaint = NSColor(calibratedRed: 0.14, green: 0.28, blue: 0.25, alpha: 1)

draw("AlejoVoice", size: 30, weight: .semibold, color: ink, centerY: 48, tracking: 0.5)
let subtitle = version.isEmpty ? "Dictado por voz local" : "Dictado por voz local · v\(version)"
draw(subtitle, size: 13, weight: .regular, color: inkSoft, centerY: 76)

draw("1 · Arrastra AlejoVoice a la carpeta Aplicaciones", size: 13, weight: .semibold,
     color: ink, centerY: 300)
draw("2 · Doble clic aquí para abrirla la primera vez", size: 13, weight: .semibold,
     color: ink, centerY: 328)
// macOS blocks a non-notarized app on first launch; the installer script is the
// no-Terminal way out, and it needs the right-click hint to get past the same check.
draw("(si macOS también bloquea el instalador: clic derecho → Abrir)",
     size: 11, weight: .regular, color: inkFaint, centerY: 440)
draw("Después, para actualizar: Ajustes → Buscar actualizaciones",
     size: 11, weight: .regular, color: inkFaint, centerY: 460)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
