import AppKit

let outDir = CommandLine.arguments[1]
// (puntos, escala) tal como los declara Contents.json
let variants: [(Int, Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]

func render(px: Int) -> Data {
    let side = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: side, height: side)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Cuerpo: rectangulo redondeado con margen, como manda macOS.
    let inset = side * 0.085
    let body = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = body.width * 0.2237
    let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    path.addClip()

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.20, green: 0.55, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.10, green: 0.32, blue: 0.85, alpha: 1),
    ])!
    gradient.draw(in: body, angle: -90)

    // Simbolo centrado, en blanco.
    let cfg = NSImage.SymbolConfiguration(pointSize: side * 0.46, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "checklist", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let s = symbol.size
        let origin = NSPoint(x: (side - s.width) / 2, y: (side - s.height) / 2)
        symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for (pt, scale) in variants {
    let px = pt * scale
    let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@\(scale)x.png"
    try render(px: px).write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
    images.append(["idiom": "mac", "scale": "\(scale)x", "size": "\(pt)x\(pt)", "filename": name])
    print("\(name)  \(px)x\(px)px")
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("Contents.json"))
print("Contents.json reescrito con \(images.count) entradas")
