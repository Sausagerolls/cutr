import Foundation

nonisolated enum LengthUnit: String, CaseIterable, Identifiable, Codable, Sendable {
    case millimetres = "mm"
    case centimetres = "cm"
    case inches = "in"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .millimetres: String(localized: "Millimetres")
        case .centimetres: String(localized: "Centimetres")
        case .inches: String(localized: "Inches")
        }
    }

    var symbol: String {
        switch self {
        case .millimetres: "mm"
        case .centimetres: "cm"
        case .inches: "\""
        }
    }

    /// Millimetres per one of this unit.
    var millimetres: Double {
        switch self {
        case .millimetres: 1
        case .centimetres: 10
        case .inches: 25.4
        }
    }

    func fromMillimetres(_ mm: Double) -> Double { mm / millimetres }
    func toMillimetres(_ value: Double) -> Double { value * millimetres }

    /// Formats a length for display. Inches use sixteenth fractions, e.g. `23 7/16`.
    func format(_ mm: Double, includeSymbol: Bool = false) -> String {
        let value = fromMillimetres(mm)
        let text: String
        switch self {
        case .millimetres:
            text = Self.decimal(value, maxFraction: 1)
        case .centimetres:
            text = Self.decimal(value, maxFraction: 2)
        case .inches:
            text = Self.fraction(value)
        }
        guard includeSymbol else { return text }
        return self == .inches ? text + symbol : text + " " + symbol
    }

    /// Parses user input in this unit and returns millimetres.
    /// Accepts decimals (`12.5`), fractions (`3/4`) and mixed numbers (`12 3/4`, `12-3/4`).
    func parse(_ text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "-", with: " ")
        guard !cleaned.isEmpty else { return nil }
        var total = 0.0
        for token in cleaned.split(separator: " ", omittingEmptySubsequences: true) {
            if token.contains("/") {
                let pieces = token.split(separator: "/")
                guard pieces.count == 2, let n = Double(pieces[0]), let d = Double(pieces[1]), d != 0
                else { return nil }
                total += n / d
            } else {
                guard let v = Double(token) else { return nil }
                total += v
            }
        }
        guard total.isFinite, total >= 0 else { return nil }
        return toMillimetres(total)
    }

    private static func decimal(_ value: Double, maxFraction: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxFraction)).grouping(.never))
    }

    private static func fraction(_ value: Double) -> String {
        let sixteenths = Int((value * 16).rounded())
        let whole = sixteenths / 16
        var numerator = sixteenths % 16
        guard numerator != 0 else { return "\(whole)" }
        var denominator = 16
        while numerator % 2 == 0 {
            numerator /= 2
            denominator /= 2
        }
        return whole == 0 ? "\(numerator)/\(denominator)" : "\(whole) \(numerator)/\(denominator)"
    }
}

enum SettingsKey {
    static let unit = "unit"
    static let defaultKerf = "defaultKerf"
    static let defaultEdgeTrim = "defaultEdgeTrim"
    static let defaultSheetLength = "defaultSheetLength"
    static let defaultSheetWidth = "defaultSheetWidth"
    static let defaultSheetThickness = "defaultSheetThickness"
    static let projectSort = "projectSort"
    static let projectSortAscending = "projectSortAscending"
}
