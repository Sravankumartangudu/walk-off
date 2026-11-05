// Renders the background for the WalkOff.dmg installer window (640×400, plus @2x).
//   swift Icon/make_dmg_background.swift <out.tiff>
// build.sh --dist runs this; icons sit at (160, 190) and (480, 190) in Finder's top-left coordinates.
import AppKit

let w = 640.0, h = 400.0
func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
let ink = hex(0x0B2A44), purple = hex(0x0E8C8C)

func render(scale: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w) * scale, pixelsHigh: Int(h) * scale,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    cg.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

    let bg = CGGradient(colorsSpace: nil, colors: [hex(0xC9F5EA).cgColor, hex(0xD6ECF7).cgColor, hex(0xE6E9FB).cgColor] as CFArray,
                        locations: [0, 0.55, 1])!
    cg.drawLinearGradient(bg, start: CGPoint(x: 0, y: h), end: .zero, options: [])

    // Puffy clouds and a soft hill.
    func cloud(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) {
        cg.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        for (dx, dy, d) in [(-0.5, 0.0, 0.7), (0.0, 0.25, 1.0), (0.55, 0.05, 0.75), (0.1, -0.12, 0.8)] as [(CGFloat, CGFloat, CGFloat)] {
            cg.fillEllipse(in: CGRect(x: x + dx * s - d * s / 2, y: y + dy * s - d * s / 2, width: d * s, height: d * s))
        }
    }
    cloud(70, h - 60, 46)
    cloud(560, h - 44, 38)
    cloud(330, h - 32, 26)
    let hill = CGMutablePath()
    hill.move(to: .zero)
    hill.addLine(to: CGPoint(x: 0, y: 58))
    hill.addCurve(to: CGPoint(x: w, y: 52), control1: CGPoint(x: w * 0.3, y: 96), control2: CGPoint(x: w * 0.7, y: 24))
    hill.addLine(to: CGPoint(x: w, y: 0))
    hill.closeSubpath()
    cg.addPath(hill)
    cg.setFillColor(hex(0x9FDCD0).cgColor)
    cg.fillPath()

    // Dotted purple arc from the app to Applications, ending in an arrowhead.
    let y = h - 190
    let arc = CGMutablePath()
    arc.move(to: CGPoint(x: 245, y: y))
    arc.addQuadCurve(to: CGPoint(x: 385, y: y), control: CGPoint(x: 315, y: y + 40))
    cg.addPath(arc.copy(dashingWithPhase: 0, lengths: [2, 12]).copy(strokingWithWidth: 5, lineCap: .round, lineJoin: .round, miterLimit: 10))
    cg.move(to: CGPoint(x: 398, y: y - 4))
    cg.addLine(to: CGPoint(x: 376, y: y + 12))
    cg.addLine(to: CGPoint(x: 380, y: y - 12))
    cg.closePath()
    cg.setFillColor(purple.cgColor)
    cg.fillPath()

    // Finder draws icon labels in black (Light Mode) or white (Dark Mode); a mid-grey nameplate
    // under each label keeps both readable on the light background.
    for x in [160.0, 480.0] {
        let plate = CGPath(roundedRect: CGRect(x: x - 75, y: h - 283, width: 150, height: 28),
                           cornerWidth: 14, cornerHeight: 14, transform: nil)
        cg.addPath(plate)
        cg.setFillColor(ink.withAlphaComponent(0.35).cgColor)
        cg.fillPath()
    }

    func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, y: CGFloat, kern: CGFloat = 0) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        var font = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { font = f }
        let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para, .kern: kern])
        str.draw(in: CGRect(x: 0, y: y, width: w, height: size * 1.5))
    }
    text("👀 WALK OFF", 14, .heavy, purple, y: h - 104, kern: 2)
    text("Drag Walk Off into Applications to install", 17, .bold, ink, y: 84)
    text("First launch blocked? System Settings → Privacy & Security → Open Anyway", 11, .medium,
         ink.withAlphaComponent(0.75), y: 18)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.tiff"
// A multi-representation TIFF lets Finder pick the sharp 2x image on Retina screens.
let data = NSBitmapImageRep.tiffRepresentationOfImageReps(in: [render(scale: 1), render(scale: 2)], using: .lzw, factor: 0)!
try! data.write(to: URL(fileURLWithPath: out))
print("✓ wrote \(out)")
