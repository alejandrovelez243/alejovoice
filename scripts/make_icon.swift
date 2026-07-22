// Draws the AlejoVoice app icon — dark glass sphere with emerald aurora
// and voice ring, matching the in-app orb. Outputs a 1024px PNG.
// Usage: swift scripts/make_icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }
let colorSpace = CGColorSpaceCreateDeviceRGB()

// macOS icon grid: rounded rect with margin.
let margin: CGFloat = size * 0.09
let rect = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
let radius = rect.width * 0.225
let plate = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.addPath(plate)
ctx.clip()

// Background: near-black with a faint green cast.
let bg = CGGradient(colorsSpace: colorSpace, colors: [
    CGColor(red: 0.05, green: 0.09, blue: 0.07, alpha: 1),
    CGColor(red: 0.01, green: 0.03, blue: 0.02, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: size / 2, y: size), end: CGPoint(x: size / 2, y: 0), options: [])

let center = CGPoint(x: size / 2, y: size / 2)
let sphereR: CGFloat = rect.width * 0.30

func drawRadial(colors: [CGColor], locations: [CGFloat], at c: CGPoint, start: CGFloat, end: CGFloat) {
    let g = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
    ctx.drawRadialGradient(g, startCenter: c, startRadius: start, endCenter: c, endRadius: end,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

// Voice ring.
ctx.saveGState()
ctx.setStrokeColor(CGColor(red: 0.18, green: 0.90, blue: 0.62, alpha: 0.55))
ctx.setLineWidth(size * 0.012)
ctx.strokeEllipse(in: CGRect(x: center.x - sphereR * 1.28, y: center.y - sphereR * 1.28,
                             width: sphereR * 2.56, height: sphereR * 2.56))
ctx.restoreGState()

// Sphere: clip to circle, layer gradients.
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: center.x - sphereR, y: center.y - sphereR,
                          width: sphereR * 2, height: sphereR * 2))
ctx.clip()

// Dark glass base.
drawRadial(
    colors: [CGColor(red: 0.04, green: 0.28, blue: 0.19, alpha: 1),
             CGColor(red: 0.01, green: 0.06, blue: 0.04, alpha: 1)],
    locations: [0, 1],
    at: CGPoint(x: center.x - sphereR * 0.25, y: center.y + sphereR * 0.3),
    start: sphereR * 0.1, end: sphereR * 1.3
)
ctx.setBlendMode(.screen)
// Emerald aurora, bottom-left.
drawRadial(
    colors: [CGColor(red: 0.16, green: 1.0, blue: 0.65, alpha: 1),
             CGColor(red: 0.16, green: 1.0, blue: 0.65, alpha: 0)],
    locations: [0, 1],
    at: CGPoint(x: center.x - sphereR * 0.35, y: center.y - sphereR * 0.55),
    start: 0, end: sphereR * 1.25
)
// Cyan aurora, right.
drawRadial(
    colors: [CGColor(red: 0.05, green: 0.85, blue: 1.0, alpha: 0.9),
             CGColor(red: 0.05, green: 0.85, blue: 1.0, alpha: 0)],
    locations: [0, 1],
    at: CGPoint(x: center.x + sphereR * 0.6, y: center.y - sphereR * 0.15),
    start: 0, end: sphereR * 1.0
)
// Specular highlight, top-left.
drawRadial(
    colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.65),
             CGColor(red: 1, green: 1, blue: 1, alpha: 0)],
    locations: [0, 1],
    at: CGPoint(x: center.x - sphereR * 0.35, y: center.y + sphereR * 0.55),
    start: 0, end: sphereR * 0.55
)
ctx.setBlendMode(.normal)
ctx.restoreGState()

// Crisp rim.
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.20))
ctx.setLineWidth(size * 0.006)
ctx.strokeEllipse(in: CGRect(x: center.x - sphereR, y: center.y - sphereR,
                             width: sphereR * 2, height: sphereR * 2))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
