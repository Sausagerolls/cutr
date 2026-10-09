// Renders the Cutr app icon variants. Run: swift Scripts/make-icon.swift <output-dir>
import AppKit
import CoreGraphics

enum Variant { case light, dark, tinted }

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ variant: Variant, to url: URL) {
    let size = 1024
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let cg = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                       space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // Flip to top-left origin.
    cg.translateBy(x: 0, y: CGFloat(size))
    cg.scaleBy(x: 1, y: -1)
    let full = CGRect(x: 0, y: 0, width: size, height: size)

    // Background.
    switch variant {
    case .light:
        let g = CGGradient(colorsSpace: space, colors: [rgb(0xF6A84A), rgb(0xD9621F)] as CFArray, locations: [0, 1])!
        cg.drawLinearGradient(g, start: .zero, end: CGPoint(x: 1024, y: 1024), options: [])
    case .dark:
        let g = CGGradient(colorsSpace: space, colors: [rgb(0x2A2622), rgb(0x141210)] as CFArray, locations: [0, 1])!
        cg.drawLinearGradient(g, start: .zero, end: CGPoint(x: 1024, y: 1024), options: [])
    case .tinted:
        cg.setFillColor(rgb(0x000000))
        cg.fill(full)
    }

    // The sheet, slightly rotated.
    cg.saveGState()
    cg.translateBy(x: 512, y: 500)
    cg.rotate(by: -0.12)
    let sheet = CGRect(x: -330, y: -250, width: 660, height: 500)

    // Shadow.
    if variant != .tinted {
        cg.setShadow(offset: CGSize(width: 0, height: 24), blur: 50, color: rgb(0x000000, variant == .dark ? 0.6 : 0.28))
    }
    let sheetFill: CGColor = switch variant {
    case .light: rgb(0xFFF4E2)
    case .dark: rgb(0x3A332C)
    case .tinted: rgb(0xFFFFFF, 0.28)
    }
    cg.setFillColor(sheetFill)
    cg.addPath(CGPath(roundedRect: sheet, cornerWidth: 26, cornerHeight: 26, transform: nil))
    cg.fillPath()
    cg.setShadow(offset: .zero, blur: 0, color: nil)

    // Guillotine layout of parts, with a gap representing the kerf.
    let gap: CGFloat = 16
    let inner = sheet.insetBy(dx: 34, dy: 34)
    let pieces: [(CGRect, UInt32)] = [
        (CGRect(x: inner.minX, y: inner.minY, width: 300, height: 210), 0xF7CF4D),
        (CGRect(x: inner.minX + 300 + gap, y: inner.minY, width: inner.width - 300 - gap, height: 130), 0x5BA8D9),
        (CGRect(x: inner.minX + 300 + gap, y: inner.minY + 130 + gap, width: 140, height: 210 - 130 - gap), 0x7FC678),
        (CGRect(x: inner.minX, y: inner.minY + 210 + gap, width: 190, height: inner.height - 210 - gap), 0x5BA8D9),
        (CGRect(x: inner.minX + 190 + gap, y: inner.minY + 210 + gap, width: 250, height: inner.height - 210 - gap), 0xEE7276),
    ]
    for (rect, color) in pieces {
        let fill: CGColor = switch variant {
        case .light: rgb(color)
        case .dark: rgb(color, 0.9)
        case .tinted: rgb(0xFFFFFF, 0.85)
        }
        cg.setFillColor(fill)
        cg.addPath(CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil))
        cg.fillPath()
    }
    cg.restoreGState()

    // Saw blade cutting into the corner of the sheet.
    let center = CGPoint(x: 760, y: 770)
    let outer: CGFloat = 190, rootR: CGFloat = 158
    let teeth = 24
    let path = CGMutablePath()
    for i in 0..<teeth {
        let a0 = CGFloat(i) / CGFloat(teeth) * 2 * .pi
        let a1 = a0 + 2 * .pi / CGFloat(teeth) * 0.72
        let a2 = a0 + 2 * .pi / CGFloat(teeth)
        let p0 = CGPoint(x: center.x + rootR * cos(a0), y: center.y + rootR * sin(a0))
        let p1 = CGPoint(x: center.x + outer * cos(a1), y: center.y + outer * sin(a1))
        let p2 = CGPoint(x: center.x + rootR * cos(a2), y: center.y + rootR * sin(a2))
        if i == 0 { path.move(to: p0) } else { path.addLine(to: p0) }
        path.addLine(to: p1)
        path.addLine(to: p2)
    }
    path.closeSubpath()

    if variant != .tinted {
        cg.setShadow(offset: CGSize(width: 0, height: 16), blur: 36, color: rgb(0x000000, 0.35))
    }
    let bladeColor: CGColor = switch variant {
    case .light: rgb(0x2F3437)
    case .dark: rgb(0xD8DDE0)
    case .tinted: rgb(0xFFFFFF)
    }
    cg.setFillColor(bladeColor)
    cg.addPath(path)
    cg.fillPath()
    cg.setShadow(offset: .zero, blur: 0, color: nil)

    // Blade hub and expansion slots.
    let accent: CGColor = switch variant {
    case .light: rgb(0xF6A84A)
    case .dark: rgb(0xF29A3D)
    case .tinted: rgb(0x000000)
    }
    cg.setStrokeColor(accent)
    cg.setLineWidth(10)
    cg.setLineCap(.round)
    for i in 0..<4 {
        let a = CGFloat(i) * .pi / 2 + .pi / 4
        cg.move(to: CGPoint(x: center.x + 70 * cos(a), y: center.y + 70 * sin(a)))
        cg.addLine(to: CGPoint(x: center.x + 118 * cos(a), y: center.y + 118 * sin(a)))
    }
    cg.strokePath()
    cg.setFillColor(accent)
    cg.fillEllipse(in: CGRect(x: center.x - 42, y: center.y - 42, width: 84, height: 84))
    cg.setFillColor(bladeColor)
    cg.fillEllipse(in: CGRect(x: center.x - 18, y: center.y - 18, width: 36, height: 36))

    let image = cg.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    // Remove alpha for the App Store icon.
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
render(.light, to: out.appendingPathComponent("AppIcon.png"))
render(.dark, to: out.appendingPathComponent("AppIcon-Dark.png"))
render(.tinted, to: out.appendingPathComponent("AppIcon-Tinted.png"))
print("Icons written to \(out.path)")
