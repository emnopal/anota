// Renders the app icon: assets/AppIcon.icns. Run: swift scripts/make-icon.swift
// A macOS-style squircle with a code sheet: syntax-coloured lines and a text caret.
import AppKit

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    // Squircle body (Apple grid: 824pt shape centred on 1024 canvas), with a soft drop shadow.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill(); shape.fill()
    ctx.restoreGState()
    shape.addClip()
    NSGradient(colors: [NSColor(red: 0.13, green: 0.16, blue: 0.32, alpha: 1),
                        NSColor(red: 0.27, green: 0.33, blue: 0.85, alpha: 1)])!.draw(in: body, angle: 70)
    // Top sheen.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), .clear])!
        .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)

    // Code sheet, drawn at full size then scaled about the centre so it keeps a wide margin in the Dock.
    let sheetScale: CGFloat = 0.72
    ctx.translateBy(x: 512, y: 512); ctx.scaleBy(x: sheetScale, y: sheetScale); ctx.translateBy(x: -512, y: -512)
    let sheet = NSRect(x: 220, y: 210, width: 584, height: 604)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor(white: 0.985, alpha: 1).setFill()
    NSBezierPath(roundedRect: sheet, xRadius: 56, yRadius: 56).fill()
    ctx.restoreGState()

    // Lines: (indent, [(width, colour)]) top to bottom.
    let purple = NSColor(red: 0.62, green: 0.30, blue: 0.86, alpha: 1)
    let blue = NSColor(red: 0.20, green: 0.48, blue: 0.96, alpha: 1)
    let orange = NSColor(red: 0.98, green: 0.55, blue: 0.20, alpha: 1)
    let green = NSColor(red: 0.20, green: 0.70, blue: 0.45, alpha: 1)
    let grey = NSColor(white: 0.78, alpha: 1)
    let lines: [(CGFloat, [(CGFloat, NSColor)])] = [
        (0, [(90, purple), (150, blue)]),
        (60, [(110, blue), (170, orange)]),
        (60, [(80, purple), (120, green)]),
        (0, [(60, grey)]),
        (0, [(200, grey)]),
    ]
    var y: CGFloat = 690
    for (indent, parts) in lines {
        var x = sheet.minX + 64 + indent
        for (w, c) in parts {
            c.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: 34), xRadius: 17, yRadius: 17).fill()
            x += w + 22
        }
        y -= 92
    }
    // Caret after the last line.
    blue.setFill()
    NSBezierPath(roundedRect: NSRect(x: sheet.minX + 64 + 222, y: y + 92 - 14, width: 14, height: 62), xRadius: 7, yRadius: 7).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let set = URL(filePath: NSTemporaryDirectory()).appending(path: "AppIcon.iconset")
try? fm.removeItem(at: set)
try! fm.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(base * scale).representation(using: .png, properties: [:])!.write(to: set.appending(path: name))
    }
}
let out = URL(filePath: fm.currentDirectoryPath).appending(path: "assets/AppIcon.icns")
let p = Process()
p.executableURL = URL(filePath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", out.path]
try! p.run(); p.waitUntilExit()
try! render(1024).representation(using: .png, properties: [:])!.write(to: URL(filePath: fm.currentDirectoryPath).appending(path: "assets/AppIcon.png"))
print(p.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")
