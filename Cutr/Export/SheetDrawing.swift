import UIKit

/// Draws a sheet layout into a Core Graphics context. Shared by the on-screen
/// diagram and the PDF export so both always match.
nonisolated enum SheetDrawing {
    struct Style {
        var sheetFill: UIColor
        var sheetStroke: UIColor
        var trimFill: UIColor
        var offcutStroke: UIColor
        var partStroke: UIColor
        var text: UIColor
        var secondaryText: UIColor
        var partAlpha: CGFloat

        static func screen(dark: Bool) -> Style {
            Style(
                sheetFill: dark ? UIColor(white: 0.16, alpha: 1) : UIColor(red: 0.96, green: 0.93, blue: 0.87, alpha: 1),
                sheetStroke: dark ? UIColor(white: 0.5, alpha: 1) : UIColor(white: 0.35, alpha: 1),
                trimFill: dark ? UIColor(white: 0.1, alpha: 1) : UIColor(red: 0.88, green: 0.84, blue: 0.77, alpha: 1),
                offcutStroke: dark ? UIColor(white: 0.4, alpha: 1) : UIColor(white: 0.6, alpha: 1),
                partStroke: dark ? UIColor(white: 0.9, alpha: 0.9) : UIColor(white: 0.15, alpha: 0.9),
                text: dark ? .white : UIColor(white: 0.08, alpha: 1),
                secondaryText: dark ? UIColor(white: 0.85, alpha: 1) : UIColor(white: 0.25, alpha: 1),
                partAlpha: dark ? 0.75 : 0.85)
        }

        static let print = Style(
            sheetFill: UIColor(white: 0.97, alpha: 1),
            sheetStroke: .black,
            trimFill: UIColor(white: 0.88, alpha: 1),
            offcutStroke: UIColor(white: 0.6, alpha: 1),
            partStroke: .black,
            text: .black,
            secondaryText: UIColor(white: 0.2, alpha: 1),
            partAlpha: 0.55)
    }

    static let palette: [UIColor] = [
        UIColor(red: 0.95, green: 0.62, blue: 0.29, alpha: 1),
        UIColor(red: 0.36, green: 0.66, blue: 0.85, alpha: 1),
        UIColor(red: 0.50, green: 0.78, blue: 0.47, alpha: 1),
        UIColor(red: 0.93, green: 0.45, blue: 0.47, alpha: 1),
        UIColor(red: 0.69, green: 0.55, blue: 0.86, alpha: 1),
        UIColor(red: 0.98, green: 0.82, blue: 0.33, alpha: 1),
        UIColor(red: 0.35, green: 0.78, blue: 0.76, alpha: 1),
        UIColor(red: 0.89, green: 0.56, blue: 0.75, alpha: 1),
        UIColor(red: 0.67, green: 0.73, blue: 0.40, alpha: 1),
        UIColor(red: 0.58, green: 0.67, blue: 0.93, alpha: 1),
    ]

    static func color(_ index: Int) -> UIColor {
        palette[((index % palette.count) + palette.count) % palette.count]
    }

    /// Aspect ratio (width / height) of a sheet as drawn: length runs horizontally.
    static func aspect(_ sheet: SheetLayout) -> CGFloat {
        guard sheet.stock.width > 0 else { return 2 }
        return sheet.stock.length / sheet.stock.width
    }

    /// Draws the sheet scaled to fit `rect`. Call between UIGraphicsPush/PopContext
    /// or inside a UIGraphics renderer so text drawing works.
    static func draw(_ sheet: SheetLayout, in rect: CGRect, unit: LengthUnit, trim: Double, style: Style, context cg: CGContext) {
        let length = sheet.stock.length, width = sheet.stock.width
        guard length > 0, width > 0 else { return }
        let scale = min(rect.width / length, rect.height / width)
        let origin = CGPoint(x: rect.midX - length * scale / 2, y: rect.midY - width * scale / 2)
        func map(_ r: CGRect) -> CGRect {
            CGRect(x: origin.x + r.minX * scale, y: origin.y + r.minY * scale,
                   width: r.width * scale, height: r.height * scale)
        }
        let sheetRect = map(CGRect(x: 0, y: 0, width: length, height: width))

        cg.saveGState()
        defer { cg.restoreGState() }

        // Sheet, with the trimmed border shaded.
        cg.setFillColor((trim > 0 ? style.trimFill : style.sheetFill).cgColor)
        cg.fill(sheetRect)
        if trim > 0 {
            cg.setFillColor(style.sheetFill.cgColor)
            cg.fill(map(CGRect(x: trim, y: trim, width: length - 2 * trim, height: width - 2 * trim)))
        }

        // Offcuts, dashed.
        cg.saveGState()
        cg.setStrokeColor(style.offcutStroke.cgColor)
        cg.setLineWidth(0.5)
        cg.setLineDash(phase: 0, lengths: [3, 3])
        for offcut in sheet.offcuts where offcut.width * scale > 6 && offcut.height * scale > 6 {
            cg.stroke(map(offcut).insetBy(dx: 0.5, dy: 0.5))
        }
        cg.restoreGState()

        // Parts.
        let fontSize = max(7, min(14, min(sheetRect.width, sheetRect.height) / 15))
        for placement in sheet.placements {
            let r = map(placement.rect)
            cg.setFillColor(color(placement.colorIndex).withAlphaComponent(style.partAlpha).cgColor)
            cg.fill(r)
            cg.setStrokeColor(style.partStroke.cgColor)
            cg.setLineWidth(0.75)
            cg.stroke(r.insetBy(dx: 0.375, dy: 0.375))
            drawLabel(placement, in: r, unit: unit, fontSize: fontSize, style: style)
        }

        cg.setStrokeColor(style.sheetStroke.cgColor)
        cg.setLineWidth(1.25)
        cg.stroke(sheetRect)
    }

    private static func drawLabel(_ p: Placement, in r: CGRect, unit: LengthUnit, fontSize: CGFloat, style: Style) {
        guard r.width > 10, r.height > 8 else { return }
        let title = p.label
        let dims = "\(unit.format(p.length)) × \(unit.format(p.width))"
        let titleFont = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let dimFont = UIFont.monospacedDigitSystemFont(ofSize: fontSize * 0.85, weight: .regular)
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        center.lineBreakMode = .byClipping

        let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: style.text, .paragraphStyle: center]
        let dimAttrs: [NSAttributedString.Key: Any] = [.font: dimFont, .foregroundColor: style.secondaryText, .paragraphStyle: center]
        let titleSize = (title as NSString).size(withAttributes: titleAttrs)
        let dimSize = (dims as NSString).size(withAttributes: dimAttrs)

        let showDims = dimSize.width + 4 <= r.width && titleSize.height + dimSize.height + 2 <= r.height
        let rotateDims = !showDims && dimSize.width + 4 <= r.height && titleSize.height + dimSize.height <= r.width

        if showDims {
            let total = titleSize.height + dimSize.height
            let top = r.midY - total / 2
            (title as NSString).draw(in: CGRect(x: r.minX, y: top, width: r.width, height: titleSize.height), withAttributes: titleAttrs)
            (dims as NSString).draw(in: CGRect(x: r.minX, y: top + titleSize.height, width: r.width, height: dimSize.height), withAttributes: dimAttrs)
        } else if rotateDims, let cg = UIGraphicsGetCurrentContext() {
            cg.saveGState()
            cg.translateBy(x: r.midX, y: r.midY)
            cg.rotate(by: -.pi / 2)
            let total = titleSize.height + dimSize.height
            (title as NSString).draw(in: CGRect(x: -r.height / 2, y: -total / 2, width: r.height, height: titleSize.height), withAttributes: titleAttrs)
            (dims as NSString).draw(in: CGRect(x: -r.height / 2, y: -total / 2 + titleSize.height, width: r.height, height: dimSize.height), withAttributes: dimAttrs)
            cg.restoreGState()
        } else if titleSize.width <= r.width && titleSize.height <= r.height {
            (title as NSString).draw(in: CGRect(x: r.minX, y: r.midY - titleSize.height / 2, width: r.width, height: titleSize.height), withAttributes: titleAttrs)
        }
    }
}
