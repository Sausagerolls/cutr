import Foundation
import CoreGraphics

/// A corner of a part's outline, in millimetres. x runs along the part's
/// length and y along its width, with the origin at the top-left.
nonisolated struct ShapePoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

/// Geometry helpers for non-rectangular parts. A shaped part is cut from a
/// rectangular blank (its bounding box), so the optimiser packs blanks.
nonisolated enum PartShape {
    static let epsilon = 1e-6

    static func rectangle(length: Double, width: Double) -> [ShapePoint] {
        [ShapePoint(x: 0, y: 0), ShapePoint(x: length, y: 0),
         ShapePoint(x: length, y: width), ShapePoint(x: 0, y: width)]
    }

    static func bounds(_ points: [ShapePoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Shoelace formula.
    static func area(_ points: [ShapePoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        var sum = 0.0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    static func centroid(_ points: [ShapePoint]) -> ShapePoint {
        let a = area(points)
        guard a > epsilon else {
            let b = bounds(points)
            return ShapePoint(x: b.midX, y: b.midY)
        }
        var cx = 0.0, cy = 0.0, signed = 0.0
        for i in points.indices {
            let p = points[i], q = points[(i + 1) % points.count]
            let cross = p.x * q.y - q.x * p.y
            signed += cross
            cx += (p.x + q.x) * cross
            cy += (p.y + q.y) * cross
        }
        signed /= 2
        return ShapePoint(x: cx / (6 * signed), y: cy / (6 * signed))
    }

    /// Moves the outline so its bounding box starts at the origin.
    static func normalized(_ points: [ShapePoint]) -> [ShapePoint] {
        let b = bounds(points)
        return points.map { ShapePoint(x: $0.x - b.minX, y: $0.y - b.minY) }
    }

    /// True when the outline is just its own bounding rectangle.
    static func isRectangle(_ points: [ShapePoint]) -> Bool {
        let simplified = removingCollinear(points)
        guard simplified.count == 4 else { return false }
        let b = bounds(simplified)
        let corners = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                       CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)]
        return simplified.allSatisfy { p in
            corners.contains { abs($0.x - p.x) < 0.01 && abs($0.y - p.y) < 0.01 }
        }
    }

    /// Drops points that sit on a straight line between their neighbours.
    static func removingCollinear(_ points: [ShapePoint]) -> [ShapePoint] {
        guard points.count > 3 else { return points }
        var result: [ShapePoint] = []
        for i in points.indices {
            let prev = points[(i + points.count - 1) % points.count]
            let p = points[i]
            let next = points[(i + 1) % points.count]
            let cross = (p.x - prev.x) * (next.y - p.y) - (p.y - prev.y) * (next.x - p.x)
            if abs(cross) > 0.01 { result.append(p) }
        }
        return result.count >= 3 ? result : points
    }

    /// Rotates 90° clockwise inside a blank whose y extent is `width`,
    /// matching how the optimiser turns a part on the sheet.
    static func rotatedClockwise(_ points: [ShapePoint], width: Double) -> [ShapePoint] {
        points.map { ShapePoint(x: width - $0.y, y: $0.x) }
    }

    /// False when any two non-adjacent edges cross, or points repeat.
    static func isSimple(_ points: [ShapePoint]) -> Bool {
        let n = points.count
        guard n >= 3 else { return false }
        for i in 0..<n {
            let a1 = points[i], a2 = points[(i + 1) % n]
            if abs(a1.x - a2.x) < epsilon && abs(a1.y - a2.y) < epsilon { return false }
            for j in (i + 1)..<n {
                // Skip edges that share a point.
                if j == i || (j + 1) % n == i || (i + 1) % n == j { continue }
                let b1 = points[j], b2 = points[(j + 1) % n]
                if segmentsIntersect(a1, a2, b1, b2) { return false }
            }
        }
        return area(points) > epsilon
    }

    private static func segmentsIntersect(_ p1: ShapePoint, _ p2: ShapePoint, _ q1: ShapePoint, _ q2: ShapePoint) -> Bool {
        func orient(_ a: ShapePoint, _ b: ShapePoint, _ c: ShapePoint) -> Double {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        func onSegment(_ a: ShapePoint, _ b: ShapePoint, _ c: ShapePoint) -> Bool {
            min(a.x, b.x) - epsilon <= c.x && c.x <= max(a.x, b.x) + epsilon
                && min(a.y, b.y) - epsilon <= c.y && c.y <= max(a.y, b.y) + epsilon
        }
        let d1 = orient(q1, q2, p1), d2 = orient(q1, q2, p2)
        let d3 = orient(p1, p2, q1), d4 = orient(p1, p2, q2)
        if ((d1 > epsilon && d2 < -epsilon) || (d1 < -epsilon && d2 > epsilon))
            && ((d3 > epsilon && d4 < -epsilon) || (d3 < -epsilon && d4 > epsilon)) {
            return true
        }
        if abs(d1) <= epsilon && onSegment(q1, q2, p1) { return true }
        if abs(d2) <= epsilon && onSegment(q1, q2, p2) { return true }
        if abs(d3) <= epsilon && onSegment(p1, p2, q1) { return true }
        if abs(d4) <= epsilon && onSegment(p1, p2, q2) { return true }
        return false
    }

    static func distance(_ a: ShapePoint, _ b: ShapePoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    static func encode(_ points: [ShapePoint]?) -> Data? {
        guard let points else { return nil }
        return try? JSONEncoder().encode(points)
    }

    static func decode(_ data: Data?) -> [ShapePoint]? {
        guard let data, let points = try? JSONDecoder().decode([ShapePoint].self, from: data), points.count >= 3
        else { return nil }
        return points
    }

    // MARK: Presets

    enum Preset: String, CaseIterable, Identifiable {
        case rectangle, pointedEnd, gable, triangle, rightTriangle, chamfered

        var id: String { rawValue }

        var title: String {
            switch self {
            case .rectangle: String(localized: "Rectangle")
            case .pointedEnd: String(localized: "Pointed End")
            case .gable: String(localized: "Gable (Pointed Top)")
            case .triangle: String(localized: "Triangle")
            case .rightTriangle: String(localized: "Right-Angled Triangle")
            case .chamfered: String(localized: "Chamfered Corners")
            }
        }

        var systemImage: String {
            switch self {
            case .rectangle: "rectangle"
            case .pointedEnd: "arrowshape.right"
            case .gable: "house"
            case .triangle: "triangle"
            case .rightTriangle: "righttriangle"
            case .chamfered: "octagon"
            }
        }

        /// Builds the preset inside a blank of the given size.
        func points(length l: Double, width w: Double) -> [ShapePoint] {
            switch self {
            case .rectangle:
                return PartShape.rectangle(length: l, width: w)
            case .pointedEnd:
                let p = min(w / 2, l / 2)
                return [ShapePoint(x: 0, y: 0), ShapePoint(x: l - p, y: 0), ShapePoint(x: l, y: w / 2),
                        ShapePoint(x: l - p, y: w), ShapePoint(x: 0, y: w)]
            case .gable:
                let p = min(w / 3, l / 2)
                return [ShapePoint(x: 0, y: p), ShapePoint(x: l / 2, y: 0), ShapePoint(x: l, y: p),
                        ShapePoint(x: l, y: w), ShapePoint(x: 0, y: w)]
            case .triangle:
                return [ShapePoint(x: l / 2, y: 0), ShapePoint(x: l, y: w), ShapePoint(x: 0, y: w)]
            case .rightTriangle:
                return [ShapePoint(x: 0, y: 0), ShapePoint(x: l, y: w), ShapePoint(x: 0, y: w)]
            case .chamfered:
                let c = (min(l, w) * 0.15).rounded()
                return [ShapePoint(x: c, y: 0), ShapePoint(x: l - c, y: 0), ShapePoint(x: l, y: c),
                        ShapePoint(x: l, y: w - c), ShapePoint(x: l - c, y: w), ShapePoint(x: c, y: w),
                        ShapePoint(x: 0, y: w - c), ShapePoint(x: 0, y: c)]
            }
        }
    }
}
