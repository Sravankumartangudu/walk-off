// Renders the app icon: an open eye inside Face ID–style corner brackets, with a keyhole in the pupil,
// on a mint-to-ocean tile.
//   swift Icon/make_icon.swift   → writes Icon/AppIcon.icns and Icon/AppIcon.png
import AppKit

let size = 1024.0

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
let white = hex(0xFFFFFF), ink = hex(0x0B1E33)

func renderFull(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    cg.scaleBy(x: CGFloat(px) / size, y: CGFloat(px) / size)
    draw(cg)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// Every size is shrunk from one full-size drawing. Shadow and glow blur are measured in device pixels, so
// drawing straight at 16–64 px would spill them over the whole image as a faint grey square.
enum Full {
    static let png = renderFull(1024)
    static let image = NSBitmapImageRep(data: png)!.cgImage!
}

func render(_ px: Int) -> Data {
    if px == Full.image.width { return Full.png }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.interpolationQuality = .high
    ctx.draw(Full.image, in: CGRect(x: 0, y: 0, width: px, height: px))
    return rep.representation(using: .png, properties: [:])!
}

func draw(_ cg: CGContext) {
    // Body follows Apple's icon grid: 824pt squircle centred in a 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: hex(0x000000, 0.3))
    cg.addPath(squircle)
    cg.setFillColor(white)
    cg.fillPath()
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(squircle)
    cg.clip()
    let tile = CGGradient(colorsSpace: nil, colors: [hex(0x3FE0BE), hex(0x129A9E), hex(0x0B3F78)] as CFArray, locations: [0, 0.5, 1])!
    cg.drawLinearGradient(tile, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Soft light from the top left.
    let glow = CGGradient(colorsSpace: nil, colors: [hex(0xFFFFFF, 0.28), hex(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    cg.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 800), startRadius: 0, endCenter: CGPoint(x: 330, y: 800), endRadius: 520, options: [])

    // Face ID–style corner brackets.
    let (l, r, b, t, arm, bend) = (232.0, 792.0, 232.0, 792.0, 120.0, 70.0)
    cg.setStrokeColor(white)
    cg.setLineWidth(46)
    cg.setLineCap(.round)
    for (x, y, sx, sy) in [(l, t, 1.0, -1.0), (r, t, -1.0, -1.0), (l, b, 1.0, 1.0), (r, b, -1.0, 1.0)] {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x, y: y + sy * arm))
        p.addLine(to: CGPoint(x: x, y: y + sy * bend))
        p.addQuadCurve(to: CGPoint(x: x + sx * bend, y: y), control: CGPoint(x: x, y: y))
        p.addLine(to: CGPoint(x: x + sx * arm, y: y))
        cg.addPath(p)
    }
    cg.strokePath()

    // The eye: an almond of two arcs.
    let c = CGPoint(x: 512, y: 512)
    let eye = CGMutablePath()
    eye.move(to: CGPoint(x: c.x - 250, y: c.y))
    eye.addQuadCurve(to: CGPoint(x: c.x + 250, y: c.y), control: CGPoint(x: c.x, y: c.y + 250))
    eye.addQuadCurve(to: CGPoint(x: c.x - 250, y: c.y), control: CGPoint(x: c.x, y: c.y - 250))
    eye.closeSubpath()
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: hex(0x00203A, 0.45))
    cg.addPath(eye)
    cg.setFillColor(white)
    cg.fillPath()
    cg.restoreGState()

    // Iris: warm amber, so it stands out from the teal tile.
    cg.saveGState()
    cg.addPath(eye)
    cg.clip()
    let iris = CGRect(x: c.x - 112, y: c.y - 112, width: 224, height: 224)
    cg.addEllipse(in: iris)
    cg.clip()
    let amber = CGGradient(colorsSpace: nil, colors: [hex(0xFFD36A), hex(0xF59E2B), hex(0xC9631A)] as CFArray, locations: [0, 0.6, 1])!
    cg.drawRadialGradient(amber, startCenter: c, startRadius: 0, endCenter: c, endRadius: 112, options: [])
    cg.restoreGState()
    cg.setStrokeColor(hex(0x8A3E0E, 0.55))
    cg.setLineWidth(8)
    cg.strokeEllipse(in: iris)

    // Pupil with a keyhole.
    cg.setFillColor(ink)
    cg.fillEllipse(in: CGRect(x: c.x - 62, y: c.y - 62, width: 124, height: 124))
    let key = CGMutablePath()
    key.addEllipse(in: CGRect(x: c.x - 20, y: c.y - 2, width: 40, height: 40))
    key.move(to: CGPoint(x: c.x - 10, y: c.y + 4))
    key.addLine(to: CGPoint(x: c.x - 18, y: c.y - 38))
    key.addLine(to: CGPoint(x: c.x + 18, y: c.y - 38))
    key.addLine(to: CGPoint(x: c.x + 10, y: c.y + 4))
    key.closeSubpath()
    cg.addPath(key)
    cg.setFillColor(hex(0xFFD36A))
    cg.fillPath()
    // Catch-light.
    cg.setFillColor(hex(0xFFFFFF, 0.9))
    cg.fillEllipse(in: CGRect(x: c.x + 46, y: c.y + 40, width: 40, height: 40))
    cg.restoreGState()
}

let iconset = URL(fileURLWithPath: "Icon/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
try! Full.png.write(to: URL(fileURLWithPath: "Icon/AppIcon.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Icon/AppIcon.icns"]
try! p.run()
p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("✓ Icon/AppIcon.icns")
